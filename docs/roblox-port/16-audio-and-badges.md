# Music, remaining SFX wiring, and badges (Phase 6)

Ports `Audio/AudioManager.cs` + `Audio/AudioPlayer.cs` (music crossfading),
wires every `AudioManager.Instance.Play*` call site from `Entities/*.cs`,
`Player/*.cs`, `UI/*.cs`, and `Core/*.cs` that has a genuine client-visible
signal to hang off of in the current port, and ports
`Core/VariableManager.cs`'s `CheckForAchievement` onto Roblox's
`BadgeService`.

New files: `src/client/Music.client.luau`, `src/client/SfxEvents.client.luau`,
`src/shared/Badges.luau`, `src/server/BadgeService.server.luau`. Hardened:
`src/shared/SoundFX.luau`. Untouched (by design): `src/shared/SoundAssets.luau`
already had every stem this phase needed — see "No SoundAssets/manifest
changes" below.

## 1. Music index → stem mapping

`Music.client.luau` listens to `Players.LocalPlayer.LevelState.Changed`, the
`BindableEvent` `LevelClient.client.luau` already fires from the `LevelChanged`
remote (doc 13 item 6) — this phase never touches `LevelClient.client.luau`
itself, only consumes what it already publishes.

| `musicIndex` | Unity asset (doc 12 §5) | `SoundAssets` stem |
|---|---|---|
| 0 | `Audio/Music/BrusselSprouts.wav` | `music1` |
| 1 | `Audio/Music/FrogSounds.wav` | `music2` |
| 2 | `Audio/Music/Opening.mp3` | `music3` |
| 3 | `Audio/Music/Adenine.mp3` | `music4` |
| 4 | `Audio/Music/Two Wrongs.wav` (Multiplayer.unity override) | `music5` |

Per `src/shared/Levels.luau` / doc 11 §1: Menu=1, Tutorial=1, Pot=0,
Kitchen=1 — so in practice the base 4 levels only ever alternate between
`music2` and `music1`.

**Country's `musicIndex` is 4.** The base `AudioManager` prefab has only 4 clips, but
`Multiplayer.unity` — the only scene that contains the Country level — overrides
`musicClips[]` with a fifth entry, `Audio/Music/Two Wrongs.wav` → `music5`. An index
with no mapped stem fades the current track out to silence instead of erroring.

### Behaviour ported from `AudioPlayer.cs`

- Two looped `Sound` instances in `SoundService` ("MusicChannel1"/"2"),
  crossfaded by swapping which one is "active" — mirrors
  `channelIndex`/`GetNewChannelIndex()`.
- Fade time: `AudioPlayer.cs`'s `fadeAmount = .01f` applied once per `Update()`
  frame ⇒ ~100 frames to fully fade at 60fps ⇒ `FADE_SECONDS = 100/60` (~1.67s),
  done with a `TweenService` tween instead of a per-frame `Update` loop.
- Volume: `musicOnAwakeVolume = .7f` → `TARGET_VOLUME = 0.7`.
- **"soft" transitions** (level-to-level, same run) crossfade — both tracks
  briefly overlap, matching `PlayMusicClip`'s `isCrossFading` branch.
- **"death" transitions** fade the current track fully out and pause it, THEN
  fade the new `musicIndex` in — matching `LevelManager.EndLevel`'s
  `FadeOutMusic()` immediately, followed later by `SetUpLevel`/`StartLevel` →
  `PlayLevel` → `StartMusic(true, newIndex)`. The port's single
  `LevelChanged("death")` event already carries both the fade-out trigger and
  the next track in one payload (`Lane.resetRun` sets the level *before*
  calling `notify`), so this is implemented as an explicit
  fade-out-then-fade-in rather than a same-instant crossfade — that's the
  deliberate difference between how "death" and "soft" are handled.
- Same stem already playing on a repeat `LevelChanged` → no-op, no restart
  (`PlayMusicClip`'s "Triggered clip is already playing" branch).
- `SoundAssets.id(stem)` returning `nil` (id still 0) is a silent no-op
  everywhere — never errors.
- `MusicOn` player Attribute (nil = on, per this phase's contract with the
  menus agent): read on every `LevelChanged`, and reacted to live via
  `GetAttributeChangedSignal("MusicOn")` (fades out on toggle-off, resumes +
  fades in on toggle-on).

## 2. SFX coverage table

Every `AudioManager.Instance.Play*` call site found by grepping
`Entities/`, `Player/`, `UI/`, `Core/`, `Audio/` for `AudioManager.Instance`:

| Clip (`AudioManager.cs` field) | Unity call site | Port status before this phase | This phase |
|---|---|---|---|
| grabSound | `Entities/Step.cs` PlayGrabSound | wired (`GameClient.client.luau`, on `GrabStep`) | no change |
| crumbleSound | `Entities/Step.cs` | wired (`Effects.client.luau`, on... see note*) | no change |
| crumbleShortSound | `Entities/Step.cs` PlayShortCrumbleSound | wired (`Effects.client.luau`, on `ForceRelease`) | no change |
| fallSound | `Player/Frog.cs` PlayFallSound | wired (`Effects.client.luau`, on `GameOver`) | no change |
| slurpSound | `Entities/Tongue.cs` Expand, `Entities/Beam.cs` (Beam unused in port) | wired (`GameClient.client.luau`, on tongue expand) | no change |
| squishSound | `Entities/Tongue.cs` DefaultCatchAction | wired (`Effects.client.luau`, on `BugCaught`) | no change |
| missSound | `Player/Controller.cs` CheckTouch | wired (`GameClient.client.luau`, on raycast miss) | no change |
| **flySound** | `Entities/Bug.cs` OnTriggerEnter2D (fires alongside squish, `UI/HUD.cs` ChangeBugCount) | not wired | **wired** — `SfxEvents.client.luau` on `BugCaught` |
| **okVoiceSound / greatVoiceSound / perfectVoiceSound** | `Player/Player.cs` TrackGrabQuality | not wired | **wired** — `SfxEvents.client.luau` on `ScoreChanged`'s `quality` field |
| **base10Sound** | `UI/HUD.cs` StepsClimbed setter (`value % 10 == 0`) | not wired | **wired** — `SfxEvents.client.luau`, replicates the exact condition off `ScoreChanged` |
| **highScoreSound** | `UI/HUD.cs` StepsClimbed setter (`value == newHighScore`) | not wired | **wired** — `SfxEvents.client.luau`, `score == best + 1` (see doc comment for why that's equivalent) |
| **awakeSound** | `Player/Frog.cs` Rise (spawn + every respawn) | not wired | **wired** — `SfxEvents.client.luau`, off the `Dead` Attribute's false-transitions |
| **splashSound** | `Core/LevelManager.cs` Tutorial-end lava reveal (level-scripted timer, twice — live and once dead/commented) | not wired | **wired to `GameOver` instead**, per task brief ("splash on death/GameOver") — see caveat below |
| **leafSound → "leaves"** | `FirstTree*.prefab`'s own `AudioSource` (`playOnAwake`, NOT routed through `AudioManager`) | not wired | **wired** — `SfxEvents.client.luau`, on a new own-lane Step with `Sprite == "Acorn"` |
| hurtSound | `Entities/Lava.cs` FallSplash (a lava-specific death only) | not wired | **wired** (2026-09-19 follow-up, closes the doc 17 gap) — `GameServer.server.luau`'s `killFrog` now fires `GameOver`/`RunSummary` with a `cause` argument (`DEATH_CAUSE_LAVA = "Lava"`); `SfxEvents.client.luau` plays `hurt` when `cause == "Lava"`. See "3. Follow-up: doc 17 gap closures" below, including a flagged duplicate with `WorldLava.client.luau`'s own separate `hurt` trigger |
| holdOnVoiceSound | `Entities/Step.cs` ShowGuidance, **inside a fully commented-out method body** | not wired | **not wired — dead code in the original**, same as `leafSound`'s dangling name-lookup (doc 12 already flags that pattern) |
| boilVoiceSound ("BoilAFrogVO") | *no call site found anywhere in the grepped C#* | not wired | **not wired — orphaned clip, unused even in Unity** (parallel to doc 12's `leafSound`/`HotFrogVO` findings) |
| selectSound | `Core/VariableManager.cs` ToggleMusic, `UI/MenuManager.cs` | not wired | **UI-owned, left as a hook** — `SoundFX.play("select")` for the menus agent to call from its music-toggle / menu-select handlers |
| blinkSound | `UI/MenuManager.cs` | not wired | **UI-owned, left as a hook** — `SoundFX.play("blink")` |
| newSound | `UI/MenuManager.cs` (skin-unlock feedback); the one gameplay call site (`Player/Player.cs` `TouchStepEnhanced`) is itself inside a commented-out method | not wired | **UI-owned / dead code** — leave to the menus/store agent (`StoreUI.client.luau` is off-limits here) |
| hotFrogVO (`audioIntroduction`) | `UI/FrogPackages.cs` (skin equip/preview) | not wired | **UI-owned, out of scope** — store/skins territory (`StoreUI.client.luau` off-limits) |
| popSound (Bubble's `grabClip`) | `Entities/MovingScenery.cs` PlayForAll(grabClip) | not wired | **wired** (2026-09-19 follow-up, closes the doc 17 "Bubble pop" gap) — `WorldScenery.client.luau` gained its own tap-to-pop input for `SceneryKinds.luau`'s new `poppable` kinds (Bubble only); see doc 14 |

\* `crumbleSound` is referenced in `Effects.client.luau`'s header comment as
already wired; this phase didn't touch that file (off-limits) so it's left
as-is either way.

**Result:** 9 clips already wired before this phase (unchanged), 6 newly
wired this phase (`fly`, OK/Great/Perfect voice lines, `base10`, `highScore`,
`awake`, `splash`, `leaves` — 8 total counting the 3 voice lines separately),
2 wired in later 2026-09-19 follow-ups (`hurt` / lava-specific death cause —
see §3 below; `pop` / Bubble scenery — see doc 14 "Bubble pop"),
2 confirmed dead code in the original (`holdOnVoice`, `boilVoice` — not a
port gap, they don't play in Unity either), 4 left as explicit UI hooks for
the menus/store agent (`select`, `blink`, `new`, `hotFrogVO`).

## 3. SoundFX hardening

`src/shared/SoundFX.luau`:

- **Per-stem concurrency cap** (`MAX_CONCURRENT_PER_STEM = 8`): extra
  `SoundFX.play(stem)` calls beyond the cap are dropped, not queued — keeps a
  tap-spam burst from spawning unbounded `Sound` instances. A single
  `Destroying` listener per clone is the one release path (covers both the
  normal `Ended → Destroy()` route and the `Debris` 15s safety net), so the
  count can never be double-decremented.
- **`SfxOn` player Attribute** respected the same way `Music.client.luau`
  respects `MusicOn`: nil = on (may not exist yet), explicit `false` = muted.
  Checked once per `play()` call via `Players.LocalPlayer`.
- **Pitch variance**: grepped the whole Unity project for `.pitch` /
  `Random...Pitch` — no hits anywhere. Unity never randomizes pitch for any of
  these clips, so `SoundFX` doesn't add any; nothing to port.
- **`PlayForAll` semantics**: documented in the module's header comment.
  Unity's `PlayForAll` plays through one shared `AudioSource`, audible to
  whichever local player(s) that build renders for. The Roblox port has no
  such shared listener — every `SoundFX.play()` call is inherently per-client
  (whichever LocalScript called it), because every trigger already comes from
  a client-scoped signal (a `RemoteEvent` fired to one player, or a
  client-local Attribute change). There's no "play for the whole server"
  primitive here, and nothing in this port's design needs one.

## 4. Badges

`src/shared/Badges.luau`: a 10-entry `{ threshold, id, name }` table (10, 20,
… 100), ported 1:1 from `VariableManager.CheckForAchievement`'s
`Social.ReportProgress("10!"…"100!", …)` calls. All `id`s are placeholders
(`0`); `BadgeService.server.luau` skips id-0 entries silently.

`src/server/BadgeService.server.luau`:

- Discovers each player's `leaderstats.Score` `IntValue` (created by
  `GameServer.server.luau`'s `ensureLeaderstats` — this script only
  `WaitForChild`s it, never `require`s `GameServer`, so load order is moot,
  same pattern `BugService.server.luau` uses for lane discovery).
- Watches `Score.Changed` and awards a threshold the first time
  `Score.Value` crosses it upward, in **any** run — a deliberate divergence
  from Unity's "only on a new all-time high score" gate (see the module's own
  header comment for the reasoning: Roblox badges are one-time "did this
  ever" unlocks, and gating them behind beating your all-time best would lock
  most repeat players out of ever earning them).
- `BadgeService:UserHasBadgeAsync` (skip if already owned) then
  `BadgeService:AwardBadge`, both in `pcall`, both `task.spawn`'d so a slow
  Open Cloud call never blocks the score-changed handler.
- A per-session `{ [Player]: { [threshold]: true } }` cache avoids redundant
  API calls within one live session; no `DataStore` — `BadgeService` itself is
  the durable "has this badge" record.

### Creating the 10 badges

1. **Creator Hub** → creations → this experience → **Engagement** →
   **Badges** → **Create a Badge**, once per row in `Badges.luau` (suggested
   names are already in the `name` field there: "10 Steps!" … "100 Steps!").
2. Upload icon art (any square image; Roblox moderates it) and set each
   badge's display name/description.
3. Copy each badge's numeric id (from its Creator Hub page or the badge's
   asset URL) into the matching `id = 0` in `src/shared/Badges.luau`.
4. No further code changes needed — `BadgeService.server.luau` picks up
   non-zero ids automatically.

## 5. No SoundAssets / manifest changes

Every stem this phase needed (`music1`–`music4`, `okVoice`, `greatVoice`,
`perfectVoice`, `base10`, `highScore`, `awake`, `splash`, `fly`, `leaves`, and
all the previously-wired ones) was **already present** in
`src/shared/SoundAssets.luau` before this phase started — `tools/build_manifest.py`'s
`ONE_SHOT_SOUNDS`/`MUSIC` lists and `SoundAssets.luau`'s `Ids` table already
covered the full `AudioManager.cs` roster (doc 12 §5). No stems were added,
renamed, or removed, so `tools/build_manifest.py` and `tools/write_asset_ids.py`
were re-run only to confirm that (both reported "already up to date" / no
unknown keys — see the phase report for the exact command output).

## 6. Follow-up (2026-09-19): three doc 17 gap closures

A later pass closed three items from doc 17's "Known gaps" table without
touching `Lane.luau`, `Levels.luau`, `World*.client.luau`, or doc 17 itself.

**`hurt` sound / death cause.** `GameServer.server.luau`'s `killFrog` now
fires both `GameOver` and `RunSummary` with a trailing `cause` argument
(`local DEATH_CAUSE_LAVA = "Lava"`). The fall loop's only death mechanism is
the frog's head dropping past `Config.DESPAWN_Y` — this port's stand-in for
Unity's lava line — so there's only one cause today; the argument is still
explicit (not hardcoded per call site) so a future second cause only needs a
new value, not a new remote. `SfxEvents.client.luau`'s `GameOver` listener
plays `hurt` when `cause == "Lava"`, alongside the existing `splash` cue.
Neither `Effects.client.luau` (`GameOver.OnClientEvent:Connect(function()
...)`) nor `MenuClient.client.luau`'s `RunSummary` listener (both outside
this pass's file ownership) needed edits — Lua ignores an extra trailing
argument on a handler that doesn't declare a parameter for it.

**Duplicate `hurt`, since fixed:** `WorldLava.client.luau` independently
played `hurt` off a local proxy — this player's frog `Dead` attribute
flipping true, or a step recycling near the despawn line inside this lane's
X band. That predated the `cause` argument above and wasn't written with it
in mind, so a death played `hurt` twice (once from each script). A later
pass (2026-09-19) removed that proxy `hurt` call from `WorldLava.client.luau`'s
`splashAt` — the visual splash burst it drives stays, keyed to the same
proxy; only the sound was dropped. `SfxEvents.client.luau`'s `GameOver`
listener is now the sole place `hurt` plays.

**Bugs-this-run counter.** `BugService.server.luau`'s `CatchBug` handler now
fires a dedicated `ServerStorage/BugCaughtServer` `BindableEvent` (`player`
only) right alongside its existing `AwardFlys`/`BugCaught` calls, using the
same get-or-create-in-`ServerStorage` pattern as `AwardFlys`/`SpawnBugAt`.
`GameServer.server.luau` listens on it directly for its `bugsThisRun` counter
(feeding `RunSummary`), replacing the old inference of "amount fired on
`AwardFlys` == `Config.BUG_FLYS`" — a heuristic that would have silently
miscounted if that amount, or another faucet's amount, ever collided with it.
The `flysThisRun` counter is untouched (summing every `AwardFlys` amount was
always correct, never a heuristic — every source is genuine currency). The
HUD's own bug count (`GameClient.client.luau`) was already exact before this
pass — it counts `BugCaught` `RemoteEvent` events directly (doc 15 §"Bugs-
caught / Flys-earned this run"), never the `BUG_FLYS` heuristic doc 17
described — so it needed no change.

**Music toggle save debounce.** `Config.MUSIC_SAVE_DEBOUNCE = 5` (seconds).
`GameServer.server.luau`'s `SetMusicOn` handler still applies the setting
immediately every call (`profile.musicOn` and the `MusicOn` Attribute both
update unconditionally), but only calls `Profiles.save` at most once per
`MUSIC_SAVE_DEBOUNCE` seconds per player (`lastMusicSave: { [Player]: number
}`, cleared on `PlayerRemoving`). Verified this can't lose the final toggle
value: `Profiles.luau`'s `Players.PlayerRemoving` handler and `BindToClose`
both call `doSave(player, true)` unconditionally (no debounce awareness),
reading whatever `profile.musicOn` holds in memory at that moment; the
120s periodic autosave (`AUTOSAVE_INTERVAL`) covers everything in between. The
debounce only ever skips a save superseded by a newer one, never the value
itself.
