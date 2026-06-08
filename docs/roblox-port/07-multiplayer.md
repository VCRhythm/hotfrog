# 07 — Networked Multiplayer

> Builds on [02-architecture-mapping.md](02-architecture-mapping.md#decision-2-client--server-split)
> and the [reference scripts](scripts/). The basic scripts are single-player-shaped
> with some client trust; this page covers true **networked** multiplayer (multiple
> Roblox players in a live server) and the authority hardening that comes with it.

## The original is *local* multiplayer

In Hotfrog, "multiplayer" means multiple **controllers on one device**:
`Core/ControllerManager.cs` keeps a `List<Controller>`, a static `playerCount`, and
broadcasts via `TellControllers` / `TellController(playerID, ...)`. Crucially, the
pull is **global** — `Spawning/SpawnManager.cs` holds one `SpawnDirection` and one
`PullVector` applied to the whole field, so every controller shares one field of
steps and one scroll. That's couch co-op.

Porting to Roblox replaces "controllers" with networked `Player`s, and forces a
decision the original never had to make: **does everyone share one field, or does
each player get their own?**

## Decision: shared field vs. per-player fields

### Option A — Per-player fields (recommended)

Each player gets their own `Steps` folder, their own spawner, their own pull, and
their own frog. Players coexist in the same server but climb independent fields;
they compete on a shared leaderboard.

- **Pros:** no contention; the basic loop barely changes (instantiate it per
  player); trivially fair; scales to many players.
- **Cons:** not literally the couch-co-op feel; players don't share a field.
- **Visibility:** either each player only sees their own field (filter via
  `FireClient` + client-side rendering), or fields are spatially separated lanes
  in `Workspace` so everyone can see everyone.

This is the right default for a Roblox port: it matches player expectations
(individual runs, shared leaderboard) and keeps authority simple.

### Option B — Shared field (faithful co-op/competitive)

One server-owned field; every player's grabs feed one shared `PullVector` — the
literal port of `SpawnManager`. Multiple frogs hang on the same steps.

- **Pros:** true to the original's shared-pull chaos; great for co-op/versus party
  play.
- **Cons:** the server must own the single field *and* every frog's position
  (you can't let each client move its own frog freely, or scroll desyncs);
  reconciling simultaneous grabs needs a rule (the original used a single
  "commanding step" — see `SpawnManager.commandingStep`, where only one step
  drives the pull at a time and others are ignored until release).

Pick B only if shared-field play is the design goal; budget for server-authoritative
frogs and conflict rules.

## Authority & anti-exploit (required either way)

The basic [`GameServer`](scripts/GameServer.server.lua) trusts the client for two
things to stay simple: it accepts client-reported **grabs** and client-reported
**death** (`ReportDeath`). In a competitive multiplayer game with a leaderboard,
that's exploitable. Harden as follows:

| Trust in the basic scripts | Hardening for multiplayer |
|---|---|
| Client says "I grabbed step X" (`GrabStep`) | Server already owns step positions; also verify the step is *reachable* from the player's frog and not already held. Rate-limit grabs per player (a human can't grab 100×/s). |
| Client computes grab **quality** | Recompute quality on the server from the (server-known) step position and the reported tap point, or drop quality from scoring entirely. Never let the client send a score. |
| Client reports **death** (`ReportDeath`) | Make the **frog server-authoritative**: the server owns each frog's Y (driving gravity, or validating client-sent positions against a max fall speed), and the server alone decides the run ended when the frog crosses the lava line. |
| Score lives per player, pushed to that client | Keep score server-only; the client never sends a score, only *events* the server scores. |

Rule of thumb: **the client sends intents (taps/grabs), the server owns state
(steps, pull, frog position, score).** This is exactly the
[client/server split](02-architecture-mapping.md#decision-2-client--server-split)
taken to its authoritative conclusion.

### Server-authoritative frog (for Option B, and recommended for A's leaderboard)

Move the gravity loop from `GameClient` to the server (one Heartbeat loop over all
frogs), and send the resulting positions to clients to render. The client still
sends taps; it no longer decides where the frog is or when it dies. This removes
`ReportDeath` entirely — the server's lava check fires `GameOver`.

```lua
-- server: one fall loop for every player's frog (replaces client gravity + ReportDeath)
local frogs = {} -- [Player] = { pos = Vector3, gravityMult = number, holding = boolean }

RunService.Heartbeat:Connect(function(dt)
	for player, f in pairs(frogs) do
		if not f.holding then
			f.gravityMult += Config.GRAVITY_ACCEL * dt
			local speed = math.min(Config.GRAVITY * f.gravityMult, Config.MAX_FALL_SPEED)
			f.pos = f.pos - Vector3.new(0, speed * dt, 0)
			if f.pos.Y <= Config.DESPAWN_Y then
				commitHighScore(player); resetScore(player)
				GameOver:FireClient(player)
				f.pos = Vector3.new(0, 0, Config.PLANE_Z); f.gravityMult = Config.GRAVITY_MULT_START
			end
		end
	end
	FrogState:FireAllClients(frogs) -- clients render; they do NOT own position
end)
```

## Replication & broadcast patterns

The Unity `TellControllers` / `TellController(playerID, ...)` fan-out maps onto
Roblox remotes:

| Unity | Roblox |
|---|---|
| `TellControllers(action)` | `RemoteEvent:FireAllClients(...)` |
| `TellController(playerID, action)` | `RemoteEvent:FireClient(player, ...)` |
| `playerCount` / register | `Players.PlayerAdded` / `PlayerRemoving` bookkeeping |

For **per-player fields (Option A)**, send each client only its own field's
updates with `FireClient` (or, if fields are separate lanes everyone can see, let
server-owned parts replicate normally and just scope *score* per player).

For a **shared field (Option B)**, the field is server-owned parts that replicate
to everyone automatically; you only need remotes for inputs (grabs) and per-player
HUD/score.

## Leaderboard & persistence

- **In-session board:** use `leaderstats` (a `Folder` named `leaderstats` under
  each `Player` with an `IntValue` like `Score`) so Roblox shows the player list
  ranking for free.
- **Global high scores:** keep per-user bests in the `DataStore` you already have,
  and mirror them into an `OrderedDataStore` to query a global top-N
  (`GetSortedAsync`) for a world leaderboard surface.

```lua
Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder"); stats.Name = "leaderstats"; stats.Parent = player
	local score = Instance.new("IntValue"); score.Name = "Score"; score.Parent = stats
	-- update score.Value alongside sessionScore in addScore()/resetScore()
end)
```

## How the basic scripts change

Concretely, to take the [reference scripts](scripts/) to networked multiplayer
(Option A + hardening):

1. **Per-player field:** parameterize spawning/pool/pull by player (a `Steps_<userId>`
   folder + per-player `active` set), spun up on `PlayerAdded`, torn down on
   `PlayerRemoving`.
2. **Server-authoritative frog:** move the gravity loop server-side (snippet
   above), delete `ReportDeath`, let the server's lava check own `GameOver`.
3. **Validate grabs:** keep the reach check, recompute quality server-side, and
   add a per-player grab rate limit.
4. **leaderstats + OrderedDataStore** for visible and global ranking.

Each is independently testable with Studio's **Test → Clients and Servers** (start
2 players) — verify scores stay isolated per player, that editing one client can't
change another's score, and that a frog only dies by the server's lava check.

## Out of scope here

True shared-field conflict resolution (the `commandingStep` rule), spectating, and
matchmaking/teleport between places are larger topics — start with Option A, get a
clean competitive loop with a leaderboard, then decide whether shared-field play is
worth the extra authority work.
