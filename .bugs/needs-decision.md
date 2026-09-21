# hotfrog — questions the bug loop needs answered

## b-20260921-152537-l4vl  2026-09-21 16:25
note: the frog is holding the carrot on the very end rather than its middle
question: The carrot grip point already matches Unity's Carrot.png.meta pivot, which sits ~38% along the carrot from the blunt end, inside the art. The "very end" look comes from the closed-fist HandGrab sprite: at Unity's own scale it is ~5.4 studs wide against a ~2.5-stud-wide, ~7.8-stud-long carrot, so it covers one end. Options: (a) move the carrot grip ~1 stud toward the art's geometric middle (canvas ≈0.27, 0.37) and record it as a deviation in doc 17; (b) keep Unity's pivot; (c) look into whether the fist is drawn too big (if Unity's fist looks smaller next to a carrot, the HandGrab scale is the real bug). Which one?
context: src/shared/StepKinds.luau GRIP_CARROT / hitOffset; the HandGrab parts are in src/assets/FrogModel.model.json. The fixer could not take a screenshot (MCP screen_capture came back blank), so nothing here was checked visually.

## b-20260921-152729-o03u  2026-09-21 16:45
note: the roblox leaderboard modal gets in the way of steps. I don't want to move the modal. can we make sure steps don't stop behind it?
question: Each grab pulls the field a fixed PULL_DISTANCE and steps spawn at random heights, so a step can stop at any height, including under the PlayerList. Moving the camera doesn't help, and the server can't see screen size. Pick one: (B, recommended) the client sends the list's rough world rectangle for its own lane (camera, top-bar inset, ~340 px wide, height from the player count, only while the list is open) through a new remote, and the server makes a grab's pull longer (never shorter, at most ~1 extra pull) until no step's grab box ends up inside it; (A) the same longer pull, but against a fixed top-right reserve set in Config (simpler, wrong for either wide or narrow screens); (C) keep the fixed pull and accept the overlap. B and A would be recorded as deviations in doc 17.
context: pullLane in src/server/GameServer.server.luau (~line 1233), spawn heights in src/server/Lane.luau; B also needs a remote and camera math in src/client/GameClient.client.luau.

## b-20260921-152818-f5bf  2026-09-21 16:55
note: the frog's hand when not grabbing, is a little far off the arm (so there's a small gap)
question: In the frog model the open hand and the arm already touch exactly, going by Unity's sprite pivots (checked two ways; both edges at Y=-13.86 right, -13.76 left). The fixer thinks the gap is Roblox blurring the edges where two textured parts meet, but could not screenshot to confirm. Options: (a) overlap the hand ~1-2 source px (0.026-0.05 studs) toward the arm to hide the seam, recorded in doc 17; (b) leave it. If the gap you see is clearly bigger than a hairline, or only shows while reaching or swaying, say so: then the cause is runtime positioning, not the model, and it's a new bug.
context: RightHand/LeftHand in src/assets/FrogModel.model.json; runtime limb moves are in GameServer.
