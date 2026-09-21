# hotfrog — questions the bug loop needs answered

## b-20260921-183648-aeap  2026-09-21 19:15
note: TouchIndicator out-of-reach state uses a TextLabel red X glyph, not art -- no X sprite exists under Sprites/ for the asset pipeline to upload
question: The out-of-reach click now shows a red text "X" (same style as the quality popup's miss X), because no X image exists in Sprites/ or in the Unity TouchIndicator prefab (doc 12 §6 lists only Circle.png). Keep the text X, or add an X sprite (you'd drop a PNG under Sprites/Other/ and run the asset pipeline; the loop can then wire it)? If you remember Unity's X coming from a specific sprite or prefab, name it.
context: src/client/WorldTouchIndicator.client.luau (red X branch); art binding via SpriteSkin/SkinAssets.
