# 09 — Free Flys: Gifts & Ads

> Extension on top of the currency in
> [08-frog-skins-and-store.md](08-frog-skins-and-store.md) and the bug faucet in
> [06-bugs-and-tongue.md](06-bugs-and-tongue.md). Read those first.

Besides catching bugs, Hotfrog has two *free* faucets for the **Fly** soft
currency, and in the original they pour into the same sink — both call
`MenuManager.SpawnGiftFlys`:

- **Timed gifts** — `UI/GiftManager.cs` hands out a free gift on an escalating
  cooldown.
- **Rewarded ads** — `Ads/AdvertisingManager.cs` shows a Unity rewarded video and,
  on completion, spawns gift flys.

One ports cleanly (gifts); the other does not (ads), for reasons specific to
Roblox. Both ultimately feed the same `awardFlys` path from
[doc 08's `SkinService`](../../src/server/SkinService.server.luau).

> **Persistence note.** `SkinService` already owns one `DataStore` record per
> player (`HotfrogProfiles`). Do **not** stand up a second store that writes the
> same key. Put the gift fields (`giftSeed`, `lastGift`) on that same profile and,
> ideally, consolidate all per-player state behind a single profile module that
> both services read/write. The snippets below assume that shared `profiles[player]`.

---

## Part A — Timed gifts (`GiftManager.cs`)

**Original behavior:**

- A `giftSeed` (0–21, persisted as `"GiftSeed"`) sets the wait between gifts:
  `GetGiftTime() = clamp(round(exp(giftSeed)), 120, 21600)` seconds — i.e. the
  cooldown grows exponentially with each claim, from **2 minutes up to 6 hours**.
- `CanShowGift()` is true when `now - lastGift > GetGiftTime()`.
- `IncreaseGiftSeed()` (on claim) stamps `lastGift = now` and bumps the seed
  (capped at 21), so the *next* gift takes longer.
- `Hours/MinutesUntilGift()` drive a countdown display.
- Persisted via `PlayerPrefs`: `"GiftSeed"` and `"TimeSinceLastGift"` (a datetime
  string).

**Roblox approach:** make timing **server-authoritative** with `os.time()` — never
trust the client clock (a client could lie to claim early). Store `giftSeed` and a
`lastGift` Unix timestamp on the player profile; the server decides eligibility,
grants Flys, and tells the client the next-eligible time for its countdown.

```lua
-- ServerScriptService/GiftService (Script) -- shares profiles[player] with SkinService
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- reuse the same Remotes folder + ensure() helper pattern as the other services
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClaimGift = remotes:FindFirstChild("ClaimGift") or Instance.new("RemoteFunction", remotes)
ClaimGift.Name = "ClaimGift"
local GiftStatus = remotes:FindFirstChild("GiftStatus") or Instance.new("RemoteEvent", remotes)
GiftStatus.Name = "GiftStatus"

local GIFT_FLYS = 100 -- how many Flys a gift grants (the SpawnGiftFlys amount)

-- cooldown in seconds for a given seed (port of GetGiftTime)
local function giftTime(seed: number): number
	return math.clamp(math.round(math.exp(seed)), 120, 21600)
end

-- server-authoritative eligibility (port of CanShowGift, using os.time)
local function nextGiftAt(profile): number
	return (profile.lastGift or 0) + giftTime(profile.giftSeed or 0)
end

local function pushStatus(player)
	local p = profiles[player]
	GiftStatus:FireClient(player, nextGiftAt(p), os.time()) -- client derives countdown
end

ClaimGift.OnServerInvoke = function(player)
	local p = profiles[player]
	if not p then return false end
	if os.time() < nextGiftAt(p) then
		return false -- not ready (server clock is the source of truth)
	end
	-- grant + escalate (IncreaseGiftSeed)
	awardFlys(player, GIFT_FLYS) -- from doc 08 (bumps p.flys, replicates profile)
	p.lastGift = os.time()
	p.giftSeed = math.min((p.giftSeed or 0) + 1, 21)
	pushStatus(player)
	save(player)
	return true
end

-- on join, send the initial countdown so the button/timer is correct immediately
-- (call pushStatus(player) once the profile is loaded)
```

```lua
-- client: a gift button + countdown driven entirely by the server's status
local ClaimGift = remotes:WaitForChild("ClaimGift")
local GiftStatus = remotes:WaitForChild("GiftStatus")

local readyAt, serverNow, clientStamp = 0, 0, os.clock()
GiftStatus.OnClientEvent:Connect(function(nextAt, now)
	readyAt, serverNow, clientStamp = nextAt, now, os.clock()
end)

-- each frame/second: estimated server time = serverNow + (os.clock() - clientStamp)
-- if estimate >= readyAt -> enable the "Claim gift!" button; else show H:MM left.
-- clicking it: if ClaimGift:InvokeServer() == true, play the reward flourish.
```

> The client countdown is cosmetic; the server re-checks on `ClaimGift`. Even if a
> client shows "ready" early, the server rejects it. That's the whole point of
> moving the clock server-side.

---

## Part B — Ads (`AdvertisingManager.cs`)

**Original behavior:** a Unity **rewarded video** (`UnityEngine.Advertisements`).
`isReady` gates on the ad being loaded *and* a 60-second cooldown; on
`ShowResult.Finished` it stamps `lastAdvertisementTime` and calls `SpawnGiftFlys`.
So: *watch a video → get Flys, at most once a minute.*

**This does not port 1:1 to Roblox**, and that's the important takeaway:

- Roblox has **no third-party rewarded-video SDK** like Unity Ads, and its policies
  constrain "watch an ad, get currency" mechanics. The native ad system is
  **Immersive Ads** (auto-placed in-world ad surfaces/portals) monetized through
  **engagement-based payouts** — that's **passive developer revenue, not a
  player-facing "press to watch for a reward" button.** There's no script callback
  that says "this player finished an ad, give them 100 Flys."

So replace the ad faucet rather than reproduce it:

| Original intent | Roblox replacement |
|---|---|
| Free Flys on a short cooldown (watch ad) | the **timed gift** above (Part A) — same faucet, no ad needed |
| "Pay to skip the wait" / get Flys now | a **Developer Product** for Flys ([doc 08](08-frog-skins-and-store.md#fly-packs--developer-products-consumable-eg-1000-flys)) |
| Passive ad revenue | **Immersive Ads** placed in your world (no gameplay hook) |

If, in your timeframe, Roblox exposes a sanctioned **Rewarded Ads** API with a
completion signal, you can reintroduce the faucet: gate it **server-side** with the
same escalating/60s cooldown logic as Part A, and grant via `awardFlys`. Treat any
client "I watched it" message as untrusted — only grant on the platform's
server-verifiable completion signal.

> **Verify before building the ad path.** Roblox's advertising products and the
> rules around rewarding players change over time. Check the current
> [Roblox advertising docs](https://create.roblox.com/docs/production/monetization)
> and policy before committing to any ad-for-reward mechanic. When in doubt, ship
> the gift + Developer Product faucets, which are stable and policy-safe.

---

## Integration

Both faucets converge on the Fly currency from
[doc 08](08-frog-skins-and-store.md): `awardFlys(player, amount)` bumps
`profiles[player].flys` and replicates the profile, which the store UI reads.
Bugs ([doc 06](06-bugs-and-tongue.md)) are the third faucet. Keep them all routing
through the one `awardFlys` path so balance changes stay consistent and
server-authoritative.

## Milestones

1. Gift fields on the shared profile (`giftSeed`, `lastGift`); `GiftService`
   eligibility + claim. *Verify: claim grants Flys; the next claim is locked and
   the cooldown grows; rejoining keeps the correct countdown.*
2. Client gift button + countdown from `GiftStatus`. *Verify: button enables only
   when the server says ready; an early click is rejected.*
3. (Monetization) wire a Developer Product Fly pack as the "get Flys now"
   alternative (doc 08). *Verify: purchase grants Flys idempotently.*
4. (Optional, only if a sanctioned API exists) server-gated rewarded ad faucet.

## Still out of scope

The original's celebratory fly-spawn animation (`SpawnGiftFlys` visuals) is pure
polish — port it as a particle/`TweenService` flourish when `awardFlys` fires.
