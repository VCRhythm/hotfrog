--!strict
--[[
    Bugloop bootstrap (server). Starts BugReportService with the settings in Config, so
    the game's own scripts need no bugloop code. Vendored by `bugloop.py init`; do not
    edit: `bugloop.py upgrade` overwrites it. Edit Config.luau instead.

    Project context (optional): a ModuleScript named "BugloopContext" anywhere under
    ServerScriptService that returns a function returning a table. It is required on
    the first report, not at boot, so it may require any game module.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Config = (require :: any)(script.Parent:WaitForChild("Config")) :: { [string]: any }
local BugReportService = require(script.Parent:WaitForChild("BugReportService"))

local HOOK_NAME = "BugloopContext"
local WAIT_LIMIT = 300

local hook: (() -> { [string]: any })? = nil
local hookError: string? = nil
local hookTried = false

local function hookContext(): { [string]: any }
    if not hookTried then
        hookTried = true
        local module = ServerScriptService:FindFirstChild(HOOK_NAME, true)
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

-- Config.waitUntil delays the start, e.g. until startup tests have finished, so their
-- deliberate warnings are not auto-reported.
local waitUntil = Config.waitUntil
if type(waitUntil) == "function" then
    local started = os.clock()
    while true do
        local ok, ready = pcall(waitUntil)
        if not ok or ready or os.clock() - started > WAIT_LIMIT then
            if not ok then
                print("[BugReport] Config.waitUntil failed, starting now: " .. tostring(ready))
            end
            break
        end
        task.wait(0.1)
    end
end

local remoteParent = Config.remoteParent
BugReportService.start({
    project = Config.project,
    endpoint = Config.endpoint,
    remoteName = Config.remoteName,
    remoteParent = if type(remoteParent) == "function" then remoteParent() else remoteParent,
    createRemote = Config.createRemote,
    logLines = Config.logLines,
    enabledOutsideStudio = Config.enabledOutsideStudio,
    autoReport = Config.autoReport,
    collectContext = hookContext,
})
