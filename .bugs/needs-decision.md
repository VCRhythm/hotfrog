# hotfrog — questions the bug loop needs answered


## b-20261010-191719-3rn3  2026-10-12 13:43
note: let's make the chef a real character in the background of the kitchen who moves around and does things to the level to mess with you. he can swing a knife to break steps (with a clear swing tell)
question: How should the Chef hazard work? (a) Kitchen-only server-driven Chef whose knife swing targets one random visible step on your lane: about 1 s wind-up tell, then that step breaks and falls; never the step you are holding. (b) As (a) but it may also break the held step, dropping the frog. (c) As (a) plus other tricks (name them: throwing food, shoving steps sideways, ...). (d) Keep the Chef as cosmetic scenery. Also: how often should it swing (e.g. every 6-10 s), and only on Kitchen or on later levels too?
context: Today the Chef is a drifting scenery sprite (SceneryKinds/WorldScenery, client-only); a hazard needs a server entity in GameServer/Lane, a replicated tell for the client, and step-break rules in StepBehaviors.

## b-20261010-191757-89n1  2026-10-12 13:43
note: what could we do to make the inside of the pot seem more like a pot? (the clouds in the background not being visible would help)
question: Which Pot changes do you want? (1) Hide the cloud scenery in Pot only (the concrete part of your note). (2) Darker inner-wall vignette framing the lane so it reads as inside a vessel. (3) A metal/ceramic wall texture down both sides. (4) Denser steam and bubbles with a stronger heat tint. Pick any combination, or reply "just hide the clouds".
context: Pot visuals are client-only: WorldBackdrop.client.luau, WorldScenery.client.luau, Ambience.client.luau, tuned in WorldConfig.luau and SceneryKinds.luau.

## b-20261010-192132-5986  2026-10-12 13:43
note: the pause button doesn't seem to actually work?
question: Pause is deliberately a status-only panel today (doc 17: "a multiplayer server can't pause"), so this contradicts a recorded ruling. Do you want (a) a real pause that freezes only your own lane (scroll, spawns, gravity, step motion, bugs) via a server-side lane flag, (b) keep the status panel but rename the button (e.g. "Menu"/"Info") so it doesn't promise a pause, or (c) remove the button? For (a), should pausing be limited (e.g. a cooldown or max duration) so it can't be used to stall a hard section?
context: Button and panel in GameClient.client.luau (~lines 959-1000); a real pause needs a per-lane freeze flag in GameServer/Lane.luau and a doc 17 update.
