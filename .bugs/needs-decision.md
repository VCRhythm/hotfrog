# hotfrog — questions the bug loop needs answered

## b-20260921-152729-o03u  2026-09-21 16:45
note: the roblox leaderboard modal gets in the way of steps. I don't want to move the modal. can we make sure steps don't stop behind it?
question: Each grab pulls the field a fixed PULL_DISTANCE and steps spawn at random heights, so a step can stop at any height, including under the PlayerList. Moving the camera doesn't help, and the server can't see screen size. Pick one: (B, recommended) the client sends the list's rough world rectangle for its own lane (camera, top-bar inset, ~340 px wide, height from the player count, only while the list is open) through a new remote, and the server makes a grab's pull longer (never shorter, at most ~1 extra pull) until no step's grab box ends up inside it; (A) the same longer pull, but against a fixed top-right reserve set in Config (simpler, wrong for either wide or narrow screens); (C) keep the fixed pull and accept the overlap. B and A would be recorded as deviations in doc 17.
context: pullLane in src/server/GameServer.server.luau (~line 1233), spawn heights in src/server/Lane.luau; B also needs a remote and camera math in src/client/GameClient.client.luau.

## b-20260921-183648-aeap  2026-09-21 19:15
note: TouchIndicator out-of-reach state uses a TextLabel red X glyph, not art -- no X sprite exists under Sprites/ for the asset pipeline to upload
question: The out-of-reach click now shows a red text "X" (same style as the quality popup's miss X), because no X image exists in Sprites/ or in the Unity TouchIndicator prefab (doc 12 §6 lists only Circle.png). Keep the text X, or add an X sprite (you'd drop a PNG under Sprites/Other/ and run the asset pipeline; the loop can then wire it)? If you remember Unity's X coming from a specific sprite or prefab, name it.
context: src/client/WorldTouchIndicator.client.luau (red X branch); art binding via SpriteSkin/SkinAssets.
