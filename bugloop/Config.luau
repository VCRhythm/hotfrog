--!strict
--[[
    Bugloop settings for this project. Yours to edit: `bugloop.py init` writes it once
    and `upgrade` never touches it. Rojo syncs this one file into both Bugloop folders
    (server and client), so anything here must be valid on both sides.
]]

return {
    project = "hotfrog",
    endpoint = "http://127.0.0.1:8644/", -- this project's listener (.bugs/config.json "port")

    -- key = Enum.KeyCode.F8,
    -- logLines = 80,
    -- enabledOutsideStudio = false,

    -- Automatic error/warning reports. false turns them off; ignore holds Lua patterns.
    -- autoReport = { errors = true, warnings = true, maxPerSession = 25, ignore = { "^%[NoisySystem%]" } },
    -- AssistantCommand: probes the fixers run through the Studio MCP. GameDefs: unrelated user plugins.
    autoReport = { ignore = { "AssistantCommand", "GameDefs" } },

    -- When the project declares every remote in one place: say where, and let it create the event.
    -- remoteName = "BugReport",
    -- remoteParent = function() return game:GetService("ReplicatedStorage"):WaitForChild("Remotes") end,
    -- createRemote = false,

    -- Server only: delay the start, e.g. until startup tests finish (polled, 300 s cap).
    -- waitUntil = function() return _G.TestsComplete == true end,
}
