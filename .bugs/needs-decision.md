# hotfrog — questions the bug loop needs answered

## b-20261008-142458-vo87  2026-10-08 14:40
note: extend out the existing frog skin rewards so a player earns one after 2 runs, then 5 more runs, then 10 runs, etc
question: Today no skin is earned by playing: 4 skins are free, 4 are bought with Flys (Blue 500, Hawt 1000, Space 1500, Mystery 2000), and 4 are Game Pass only. Which skins should the run milestones (2, +5, +10, ...) give? (a) the Fly skins, cheapest unowned first, still buyable with Flys; once all 4 are owned, later milestones pay Flys instead; (b) new run-only reward skins (needs new art, or tints of existing art); (c) something else. Also say whether milestones count completed runs only (reached the Dead screen) or any run started.
context: It lands in Profiles.luau (a runs counter plus the next milestone), GameServer run end, SkinService (granting a skin), and a menu/Dead-screen popup; (a) also cuts the Fly economy the fly-sink answer (b-20261008-141652-rdl8) priced.
