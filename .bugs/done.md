# hotfrog — bugs processed by the bug loop

## b-20260919-123127-p3vu  fixed  2026-09-19 12:45
note: GameServer:552: attempt to index nil with 'CFrame' in createFrog, called from initPlayer
cause: FrogModel.model.json sets PrimaryPart only through Rojo's Ref attributes, which the plugin can fail to resolve on sync, so the cloned frog had a nil PrimaryPart.
change: GameServer sets frogTemplate.PrimaryPart to its Body child when unresolved, before any clone.
files: src/server/GameServer.server.luau
test: none
verified: tools/luau_check.sh clean on the file and on src/; not run in Studio
review: n/a

## b-20260919-135837-n9hp  closed-by-user  2026-09-19 13:59
note: I'm not seeing the frog sprites on load. the flies are also just placeholders, not using the actual sprites
resolved: from dashboard

## b-20260919-140016-dm0e  cannot-reproduce  2026-09-19 15:00
note: I'm not seeing the frog sprites on load. the flies are also just placeholders, not using the actual sprites
cause: user ruling "use mcp to do this" (b-20260919-144352-5rbt): the Studio check was run via the Roblox_Studio MCP. The texturing pipeline is correct; assetType=Image upload ids render directly, and the live frog and bug instances carry correct Suffix/Sprite attributes with non-zero Texture ids on server and client, no console errors. The original repro likely predates the working state.
change: no code change; doc 17 step 2 now records the Image-id render check as verified.
files: docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: Studio via MCP: edit-mode Decal with rbxassetid://132401989626297 rendered (screen capture); playtest inspection of Frog_<UserId>.Body.Body and BugTemplate.Art on server and client. Play-mode screen capture came back black (MCP capture limitation), so in-play confirmation is by property inspection, not a picture.
review: n/a

## b-20260919-144352-5rbt  cannot-reproduce  2026-09-19 15:00
note: DECISION: use mcp to do this (reopens b-20260919-140016-dm0e)
cause: answer to b-20260919-140016-dm0e; see that block.
change: none
files: docs/roblox-port/17-status-and-known-gaps.md
test: none
verified: see b-20260919-140016-dm0e
review: n/a

## b-20260919-155020-2sli  ignored  2026-09-19 15:55
note: AUTO warning (server): Infinite yield possible on 'ReplicatedStorage.Shared:WaitForChild("GameDefs")'
cause: not from this project. The stack is the local Studio plugin user_BuildingStatsEditor (another project's tool) waiting for a GameDefs module hotfrog does not have; nothing in the repo references GameDefs.
change: none
files: none
test: none
verified: grep for GameDefs across the repo returns nothing
review: n/a

## b-20260919-160006-wj5q  ignored  2026-09-19 16:05
note: AUTO error (server): StreamingMinRadius is not a valid member of Workspace "Workspace"
cause: not game code. The stack is 'AssistantCommand', a Luau probe the sprite fixer (entry ...150613-2ehi) ran through the Studio MCP with a wrong property name; the repo does not reference the property.
change: none
files: none
test: none
verified: grep for StreamingMinRadius across the repo returns nothing
review: n/a

## b-20260919-160013-geyo  ignored  2026-09-19 16:05
note: AUTO error (server): StreamingTargetRadius is not a valid member of Workspace "Workspace"
cause: same MCP probe as b-20260919-160006-wj5q ('AssistantCommand' stack), not game code.
change: none
files: none
test: none
verified: grep for StreamingTargetRadius across the repo returns nothing
review: n/a

## b-20260919-160647-fhkj  fixed  2026-09-19 16:20
note: AUTO warning (server): [Profiles] FrequencyGames (4272203669): session lock still held by studio-... after waiting -- proceeding anyway.
cause: every Studio play session mints a fresh random SESSION_ID (game.JobId is "" in Studio), so back-to-back playtests looked like foreign live servers to each other and paid the full stale-lock wait, then warned.
change: in load(), a foreign lock whose owner starts with "studio-" is taken over immediately and without the warning, gated by RunService:IsStudio() so production servers are unaffected.
files: src/server/Profiles.luau
test: none
verified: headless only: stylua --check, selene and tools/luau_check.sh pass on the file; not run in Studio (another fixer was driving Studio)
review: n/a
