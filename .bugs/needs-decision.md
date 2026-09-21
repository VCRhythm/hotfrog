# hotfrog — questions the bug loop needs answered

## b-20260921-152825-fzl6  2026-09-21 15:40
note: steps tend to just appear on screen rather than slide in
question: Doc 17 ("Spawner time per grab") records this as a known cost of pulling once per grab instead of Unity's per-frame scroll: new steps can surface a few studs inside the top of the view. Add a cosmetic slide-in (spawn steps further above the view, or tween new steps in from above on the client), or keep the documented deviation?
context: spawn position/timing is in src/server/Lane.luau and GameServer's pull; a client-only tween would live in a World* cosmetics script.

## b-20260921-152537-l4vl  2026-09-21 16:25
note: the frog is holding the carrot on the very end rather than its middle
question: The carrot grip point already matches Unity's Carrot.png.meta pivot, which sits ~38% along the carrot from the blunt end, inside the art. The "very end" look comes from the closed-fist HandGrab sprite: at Unity's own scale it is ~5.4 studs wide against a ~2.5-stud-wide, ~7.8-stud-long carrot, so it covers one end. Options: (a) move the carrot grip ~1 stud toward the art's geometric middle (canvas ≈0.27, 0.37) and record it as a deviation in doc 17; (b) keep Unity's pivot; (c) look into whether the fist is drawn too big (if Unity's fist looks smaller next to a carrot, the HandGrab scale is the real bug). Which one?
context: src/shared/StepKinds.luau GRIP_CARROT / hitOffset; the HandGrab parts are in src/assets/FrogModel.model.json. The fixer could not take a screenshot (MCP screen_capture came back blank), so nothing here was checked visually.
