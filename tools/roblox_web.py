#!/usr/bin/env python3
"""roblox_web.py — shared Roblox auth/HTTP helpers for the tools/ pipeline.

Ported from the `scare` project's tools/upload_asset.py (the parts that were
proven against live Roblox endpoints there). Standard library only.

What lives here and why:

  load_env_file()          Read <repo>/.env into os.environ (quote-stripping,
                           never overrides an already-set variable).
  resolve_cookie()         The .ROBLOSECURITY cookie from $ROBLOSECURITY.
  fetch_csrf_token()       Mint an X-CSRF-TOKEN from that cookie.
  web_upload_audio()       Upload audio through the cookie-authenticated
                           WEBSITE endpoint (publish.roblox.com). The Open
                           Cloud Assets API routes audio into a moderation
                           queue that is widely reported to sit in "Reviewing"
                           indefinitely; the website path — the same one the
                           Creator Hub uses when you upload by hand — clears
                           the automated audio pipeline in seconds. Verified
                           working on the scare project.
  web_verify_audio()       Non-destructive cookie + price check for the above.
  resolve_decal_image_id() Decal wrapper id -> underlying Image id via the
                           asset-delivery CDN. Needs the cookie: scare
                           live-checked that every endpoint carrying the
                           Decal's Texture is a first-party website API that
                           rejects the Open Cloud API key (the
                           asset-delivery-api/v1/assetId route 403s it), so
                           there is NO cookie-free path to the Image id
                           outside of Studio / the Luau Execution API.
  fetch_moderation_state() Open Cloud asset metadata GET ->
                           Reviewing / Approved / Rejected (needs the API key).
  wait_for_moderation()    Poll the above until terminal or timeout.

Secrets: ROBLOSECURITY is a full login credential — anyone holding it can act
as the account. Keep it in .env (gitignored) or the environment only; nothing
here ever writes it to disk or logs. Grab it from a logged-in browser:
DevTools -> Application -> Cookies -> https://www.roblox.com -> .ROBLOSECURITY.
"""

from __future__ import annotations

import base64
import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = REPO_ROOT / ".env"

# --- Endpoints ---------------------------------------------------------------

# POST here with no token returns HTTP 403 carrying a fresh `x-csrf-token`
# response header WITHOUT actually logging the session out — the canonical
# way to mint a CSRF token for the website APIs.
CSRF_URL = "https://auth.roblox.com/v2/logout"
WEB_AUDIO_URL = "https://publish.roblox.com/v1/audio"
WEB_AUDIO_VERIFY_URL = "https://publish.roblox.com/v1/audio/verify"

# Decal -> Image: the CDN returns the Decal's raw XML configuration, whose
# "Texture" Content property points at the underlying Image asset.
CDN_URL = "https://assetdelivery.roblox.com/v1/asset/?id={asset_id}"

# Open Cloud asset metadata: moderationResult.moderationState for an asset you
# own. Works regardless of which path uploaded it. Needs x-api-key (asset:read).
MODERATION_GET_URL = "https://apis.roblox.com/assets/v1/assets/{asset_id}"
MODERATION_POLL_SECONDS = 3.0

# publish.roblox.com is friendlier to a browser UA than to a bot-looking one.
WEB_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)
API_USER_AGENT = "hotfrog-tools/1.0"
REQUEST_TIMEOUT_SECONDS = 120

# Roblox serializes the Decal's Texture content in one of two equivalent forms:
#     <Content name="Texture"><url>http://www.roblox.com/asset/?id=NNN</url></Content>
#     <Content name="Texture"><url>rbxassetid://NNN</url></Content>
# Match the labelled Texture property first so an unrelated id= is never
# grabbed; the fallback is a looser scan for payloads that omit the label.
_TEXTURE_ID_RE = re.compile(rb'name="Texture".*?(?:rbxassetid://|\bid=)(\d+)', re.DOTALL)
_FALLBACK_ID_RE = re.compile(rb"(?:rbxassetid://|<url>[^<]*?\bid=)(\d+)")


class RobloxWebError(RuntimeError):
    """A website/Open Cloud call failed with a message already suitable for the user."""


# --- .env ---------------------------------------------------------------------


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1].strip()
    return value


def load_env_file(path: Path = ENV_PATH) -> None:
    """Load KEY=VALUE lines from .env into os.environ (setdefault — a value
    already exported in the shell wins). Strips one layer of surrounding
    quotes so ROBLOX_API_KEY='abc' isn't sent with literal quotes (Open Cloud
    then rejects the header as an invalid key)."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export ") :].strip()
        os.environ.setdefault(key, _strip_quotes(value))


def env_id(name: str) -> str | None:
    """A non-secret numeric id from the environment (universe/place/user id),
    quote-stripped, or None."""
    raw = os.environ.get(name)
    if not raw:
        return None
    raw = _strip_quotes(raw)
    return raw or None


def resolve_cookie(explicit: str | None = None) -> str | None:
    """The .ROBLOSECURITY cookie value from `explicit` or $ROBLOSECURITY, with a
    stray `.ROBLOSECURITY=` prefix and surrounding quotes removed. None if unset."""
    raw = explicit or os.environ.get("ROBLOSECURITY")
    if not raw:
        return None
    raw = _strip_quotes(raw)
    if raw.startswith(".ROBLOSECURITY="):
        raw = raw[len(".ROBLOSECURITY=") :]
    return raw or None


# --- HTTP ---------------------------------------------------------------------


def http_request(url: str, method: str, headers: dict, body: bytes | None = None) -> tuple[int, dict, str]:
    """Send a request; return (status, response_headers, response_text). Reads
    the body even on non-2xx so callers can surface the API's error message."""
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_SECONDS) as resp:
            return resp.status, dict(resp.headers), resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        text = ""
        try:
            text = e.read().decode("utf-8", errors="replace")
        except Exception:
            pass
        return e.code, dict(e.headers or {}), text


def _find_header(headers: dict, name: str) -> str | None:
    """Case-insensitive header lookup (dict(resp.headers) loses case-folding)."""
    target = name.lower()
    for key, value in headers.items():
        if key.lower() == target:
            return value
    return None


def fetch_csrf_token(cookie: str) -> str:
    headers = {"Cookie": f".ROBLOSECURITY={cookie}", "User-Agent": WEB_USER_AGENT}
    status, resp_headers, text = http_request(CSRF_URL, "POST", headers, body=b"")
    token = _find_header(resp_headers, "x-csrf-token")
    if token:
        return token
    raise RobloxWebError(
        f"Could not obtain an X-CSRF-TOKEN (HTTP {status}). The .ROBLOSECURITY cookie is "
        "probably missing, malformed, or expired — grab a fresh one from a logged-in browser "
        f"and set ROBLOSECURITY in .env.\n  Response: {text[:300]}"
    )


def web_headers(cookie: str, csrf: str, content_length: int | None = None) -> dict:
    headers = {
        "Cookie": f".ROBLOSECURITY={cookie}",
        "X-CSRF-TOKEN": csrf,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": WEB_USER_AGENT,
        "Origin": "https://create.roblox.com",
        "Referer": "https://create.roblox.com/",
    }
    if content_length is not None:
        headers["Content-Length"] = str(content_length)
    return headers


def post_with_csrf_retry(url: str, cookie: str, csrf: str, body: bytes) -> tuple[int, dict, str, str]:
    """POST once; if Roblox answers 403 with a rotated x-csrf-token, retry once
    with it. Returns (status, headers, text, token_in_use) so a batch caller can
    keep reusing the freshest token."""
    status, resp_headers, text = http_request(url, "POST", web_headers(cookie, csrf, len(body)), body)
    if status == 403:
        fresh = _find_header(resp_headers, "x-csrf-token")
        if fresh and fresh != csrf:
            csrf = fresh
            status, resp_headers, text = http_request(url, "POST", web_headers(cookie, csrf, len(body)), body)
    return status, resp_headers, text, csrf


def _parse_web_audio_response(status: int, text: str, what: str) -> dict:
    try:
        data = json.loads(text) if text.strip() else {}
    except json.JSONDecodeError:
        data = {}
    errors = data.get("errors") if isinstance(data, dict) else None
    if errors:
        msg = errors[0].get("message") if isinstance(errors[0], dict) else str(errors[0])
        raise RobloxWebError(f"{what} rejected by Roblox (HTTP {status}): {msg}\n  Full: {text[:400]}")
    if status in (401, 403):
        raise RobloxWebError(f"{what} unauthorized (HTTP {status}): cookie invalid/expired or wrong creator.\n  Response: {text[:400]}")
    if status in (404, 410):
        raise RobloxWebError(
            f"{what} endpoint returned HTTP {status} — the website audio endpoint may have moved. "
            "Capture the request your browser makes when uploading audio (DevTools -> Network) "
            f"and update WEB_AUDIO_URL in tools/roblox_web.py, or use --audio-via opencloud.\n  Response: {text[:400]}"
        )
    if status == 429:
        raise RobloxWebError(f"{what} rate limited (HTTP 429). Try again later.\n  Response: {text[:400]}")
    if status >= 400:
        raise RobloxWebError(f"{what} failed (HTTP {status}). Response: {text[:400]}")
    return data if isinstance(data, dict) else {}


# --- Website audio upload -----------------------------------------------------


def _audio_payload(name: str, file_bytes: bytes, group_id: str | None, include_size: bool) -> bytes:
    payload: dict = {
        "name": name,
        "file": base64.b64encode(file_bytes).decode("ascii"),
        "paymentSource": "Group" if group_id else "User",
    }
    if include_size:
        payload["fileSize"] = len(file_bytes)
    if group_id:
        payload["groupId"] = int(group_id)
    return json.dumps(payload).encode("utf-8")


def web_verify_audio(cookie: str, name: str, file_bytes: bytes, group_id: str | None = None) -> dict:
    """Non-destructive: confirms the cookie works and returns Roblox's price
    quote for the upload. Creates nothing, consumes no quota."""
    csrf = fetch_csrf_token(cookie)
    body = _audio_payload(name or "verify", file_bytes, group_id, include_size=True)
    status, _, text, _ = post_with_csrf_retry(WEB_AUDIO_VERIFY_URL, cookie, csrf, body)
    return _parse_web_audio_response(status, text, "Audio verify")


def web_upload_audio(cookie: str, name: str, file_bytes: bytes, group_id: str | None = None) -> tuple[str, dict]:
    """Upload one audio file via the website path. Returns (asset_id, raw
    response). The id is directly playable: Sound.SoundId = rbxassetid://<id>.
    The creator is the cookie's logged-in user unless group_id is given."""
    csrf = fetch_csrf_token(cookie)
    body = _audio_payload(name, file_bytes, group_id, include_size=False)
    status, _, text, _ = post_with_csrf_retry(WEB_AUDIO_URL, cookie, csrf, body)
    data = _parse_web_audio_response(status, text, "Audio upload")
    asset_id = data.get("Id") or data.get("id") or data.get("AssetId") or data.get("assetId")
    if asset_id is None:
        raise RobloxWebError(f"Audio upload succeeded but no asset id was found in the response: {text[:400]}")
    return str(asset_id), data


# --- Decal -> Image -------------------------------------------------------------


def resolve_decal_image_id(wrapper_id: int | str, cookie: str, attempts: int = 4, backoff: float = 3.0) -> int | None:
    """Resolve a Decal wrapper id to its underlying Image id via the CDN.
    Retries with backoff: a just-uploaded Decal's CDN payload can lag a few
    seconds, and the endpoint briefly rate-limits after a burst of uploads.
    Returns None if it still can't resolve (no/expired cookie, 403, or an
    unexpected payload)."""
    url = CDN_URL.format(asset_id=wrapper_id)
    headers = {"Cookie": f".ROBLOSECURITY={cookie}", "User-Agent": WEB_USER_AGENT}
    for attempt in range(max(1, attempts)):
        if attempt:
            time.sleep(backoff)
        try:
            req = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_SECONDS) as resp:
                body = resp.read()
                if resp.headers.get("Content-Encoding", "").lower() == "gzip":
                    body = gzip.decompress(body)
        except Exception:
            continue
        m = _TEXTURE_ID_RE.search(body) or _FALLBACK_ID_RE.search(body)
        if m:
            return int(m.group(1))
    return None


# --- Moderation ------------------------------------------------------------------


def fetch_moderation_state(asset_id: int | str, api_key: str) -> tuple[str | None, str]:
    """(moderationState, detail). State is Reviewing / Approved / Rejected, or
    None if it couldn't be read (propagation delay, 404, parse error)."""
    url = MODERATION_GET_URL.format(asset_id=asset_id)
    status, _, text = http_request(url, "GET", {"x-api-key": api_key, "User-Agent": API_USER_AGENT})
    if status >= 400:
        return None, f"HTTP {status}: {text[:200]}"
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return None, f"unparseable: {text[:200]}"
    mod = data.get("moderationResult") or {}
    return mod.get("moderationState"), text


DEVELOP_ASSETS_URL = "https://develop.roblox.com/v1/assets?assetIds={ids}"


def fetch_automated_moderation(asset_ids: list[int | str], cookie: str) -> dict[str, dict]:
    """Cookie-authenticated develop API: per asset id, {"moderationStatus":
    "Green"|"Red"|..., "isModerated": bool, "reviewStatus": "Pending"|...}.

    Live-checked 2026-09-19: a website-path audio upload showed
    moderationStatus=Green / isModerated=true within two minutes (i.e. playable)
    while Open Cloud still reported moderationState=Reviewing — Open Cloud's
    state tracks the slower human-review queue (reviewStatus=Pending), which does
    NOT block an owner's audio from playing in the owner's experience. Use this
    for the "is it usable yet" question and Open Cloud for "was it Rejected".
    """
    out: dict[str, dict] = {}
    ids = [str(i) for i in asset_ids]
    headers = {"Cookie": f".ROBLOSECURITY={cookie}", "User-Agent": WEB_USER_AGENT}
    for start in range(0, len(ids), 50):
        chunk = ids[start : start + 50]
        status, _, text = http_request(DEVELOP_ASSETS_URL.format(ids=",".join(chunk)), "GET", headers)
        if status >= 400:
            continue
        try:
            for row in json.loads(text).get("data", []):
                out[str(row.get("id"))] = row
        except json.JSONDecodeError:
            continue
        time.sleep(0.2)
    return out


def wait_for_moderation(asset_id: int | str, api_key: str, timeout: float, quiet: bool = False) -> str | None:
    """Poll until Approved/Rejected or timeout; returns the last state seen."""
    deadline = time.monotonic() + timeout
    last: str | None = None
    attempt = 0
    while True:
        attempt += 1
        state, _ = fetch_moderation_state(asset_id, api_key)
        if state:
            last = state
            if state in ("Approved", "Rejected"):
                return state
        if time.monotonic() > deadline:
            return last
        if not quiet and attempt % 3 == 0:
            print(f"  {asset_id}: moderation {last or 'unknown'} — still waiting...", file=sys.stderr)
        time.sleep(MODERATION_POLL_SECONDS)


load_env_file()
