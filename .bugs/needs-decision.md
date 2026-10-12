# hotfrog — questions the bug loop needs answered


## b-20261010-191719-3rn3  2026-10-12 13:43
note: let's make the chef a real character in the background of the kitchen who moves around and does things to the level to mess with you. he can swing a knife to break steps (with a clear swing tell)
question: How should the Chef hazard work? (a) Kitchen-only server-driven Chef whose knife swing targets one random visible step on your lane: about 1 s wind-up tell, then that step breaks and falls; never the step you are holding. (b) As (a) but it may also break the held step, dropping the frog. (c) As (a) plus other tricks (name them: throwing food, shoving steps sideways, ...). (d) Keep the Chef as cosmetic scenery. Also: how often should it swing (e.g. every 6-10 s), and only on Kitchen or on later levels too?
context: Today the Chef is a drifting scenery sprite (SceneryKinds/WorldScenery, client-only); a hazard needs a server entity in GameServer/Lane, a replicated tell for the client, and step-break rules in StepBehaviors.
