--!strict
--[[
    Bugloop bootstrap (client). Starts BugReportClient with the settings in Config, so
    the game's own scripts need no bugloop code. Vendored by `bugloop.py init`; do not
    edit: `bugloop.py upgrade` overwrites it. Edit Config.luau instead.

    Project context (optional): a ModuleScript named "BugloopClientContext" anywhere
    under PlayerScripts that returns a function returning a table. It is required on
    the first report, not at boot, so it may require any client module.
]]

local Players = game:GetService("Players")

local Config = (require :: any)(script.Parent:WaitForChild("Config")) :: { [string]: any }
local BugReportClient = require(script.Parent:WaitForChild("BugReportClient"))

local HOOK_NAME = "BugloopClientContext"

local hook: (() -> { [string]: any })? = nil
local hookError: string? = nil
local hookTried = false

local function hookContext(): { [string]: any }
    if not hookTried then
        hookTried = true
        local playerScripts = Players.LocalPlayer:FindFirstChildOfClass("PlayerScripts")
        local module = playerScripts and playerScripts:FindFirstChild(HOOK_NAME, true)
        if module and module:IsA("ModuleScript") then
            local ok, result = pcall(require :: any, module)
            if ok and type(result) == "function" then
                hook = result
            else
                hookError = if ok then HOOK_NAME .. " must return a function" else tostring(result)
            end
        end
    end
    if hook then
        return hook()
    end
    return if hookError then { contextHookError = hookError } else {}
end

local remoteParent = Config.remoteParent
BugReportClient.init({
    key = Config.key,
    remoteName = Config.remoteName,
    remoteParent = if type(remoteParent) == "function" then remoteParent() else remoteParent,
    enabledOutsideStudio = Config.enabledOutsideStudio,
    autoReport = Config.autoReport ~= false,
    collectContext = hookContext,
})
