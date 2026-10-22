# hotfrog — questions the bug loop needs answered

## b-20261022-151623-k8sg  2026-10-22 15:16
note: On a portrait phone, steps are still a little sparse even going straight up: Unity's spawn cadence gives about 1.3 new steps per grab, and with the 2-stud minimum pull the frog sometimes runs out of visible steps ahead. Should the port spawn more steps per grab on portrait (a deviation from Unity), or keep Unity's cadence?
question: On a portrait phone, steps are still a little sparse even going straight up: Unity's spawn cadence gives about 1.3 new steps per grab, and with the 2-stud minimum pull the frog sometimes runs out of visible steps ahead. Should the port spawn more steps per grab on portrait (a deviation from Unity), or keep Unity's cadence?
context: Raise density: increase spawns per grab (Lane spawner time per grab in src/server/Lane.luau / Config) for all directions, recorded as a doc 17 deviation. Keep Unity: no change; sparsity after the i6g3 placement fix stays as is. Found by the b-20261022-145536-i6g3 fixer's Studio bot run (vertical UpRock run starved at grab 7).
