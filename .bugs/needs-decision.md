# hotfrog — questions the bug loop needs answered

## b-20260922-101656-fxqk  2026-09-22 10:40
note: what are all these yellow things in the background?
question: The yellow dots are Unity's own "Water" overlay (Water.mat), which Pot and Tutorial both use as a boiling-water layer over the whole lane. Keep it as it is, make it fainter or sparser, or remove it?
context: Levels.luau sets overlay = "Water" for Pot/Tutorial; WorldBackdrop.client.luau renders it, with the tint coming from WorldConfig OVERLAY_COLORS.Water.
