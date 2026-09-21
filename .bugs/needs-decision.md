# hotfrog — questions the bug loop needs answered

## b-20260921-152825-fzl6  2026-09-21 15:40
note: steps tend to just appear on screen rather than slide in
question: Doc 17 ("Spawner time per grab") records this as a known cost of pulling once per grab instead of Unity's per-frame scroll: new steps can surface a few studs inside the top of the view. Add a cosmetic slide-in (spawn steps further above the view, or tween new steps in from above on the client), or keep the documented deviation?
context: spawn position/timing is in src/server/Lane.luau and GameServer's pull; a client-only tween would live in a World* cosmetics script.
