--!strict
--[[
    BugReportService — server side of the bugloop capture (see ~/.claude/skills/bugloop).

    Receives a note (+ optional client context) over the "BugReport" RemoteEvent,
    attaches server context and recent log lines, and POSTs it to the local
    bugloop listener. Falls back to printing a [BUGLOOP] line if the POST fails.

    Vendored by `bugloop.py init` into <repo>/bugloop/server and started by the
    Bugloop script next to it; no wiring in the game's own scripts. Do not edit the
    project copy: `bugloop.py upgrade` overwrites it. Settings live in ../Config.luau.

    Project context is optional, either of:
      * a ModuleScript named "BugloopContext" anywhere under ServerScriptService that
        returns a function returning a table (found by the Bugloop script), or
      * from any server script that holds state in locals:
            BugReportService.setContextProvider(function()
                return { simTick = Sim.getTick(), seed = seed }
            end)

    Requires HttpService.HttpEnabled = true (set it in default.project.json).
]]

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BugReportService = {}

export type AutoReportOptions = {
    errors: boolean?,          -- default true: uncaught script errors (with stack trace)
    warnings: boolean?,        -- default true: warn() output
    maxPerSession: number?,    -- default 25 distinct messages per play session
    ignore: { string }?,       -- Lua patterns; matching messages are never reported
}

export type StartOptions = {
    project: string?,
    endpoint: string?,
    remoteName: string?,
    remoteParent: Instance?,  -- where the RemoteEvent lives; default ReplicatedStorage
    createRemote: boolean?,   -- false: the project's own remote setup creates it; we only wait
    logLines: number?,
    enabledOutsideStudio: boolean?,
    collectContext: (() -> { [string]: any })?,
    autoReport: (AutoReportOptions | boolean)?,  -- false disables; default on
}

local REMOTE_NAME = "BugReport"
local ENDPOINT = "http://127.0.0.1:8644/"
local MAX_NOTE = 2000
-- Only self-referential tags: without these, reporting a bug (or the
-- listener-unreachable fallback) would recursively trigger another report.
-- Deliberately NOT a blanket mute for any other module/tag — e.g. a test runner's
-- own ERROR/FAIL warnings must still get through so failing test runs are
-- auto-filed. Project-specific noise goes in Config.autoReport.ignore.
local DEFAULT_IGNORE = {
    "^%[BugReport%]",
    "^%[BUGLOOP%]",
}

local _opts: StartOptions = {}
local _remote: RemoteEvent? = nil
local _provider: (() -> { [string]: any })? = nil
local _snaps: { [Player]: string } = setmetatable({}, { __mode = "k" }) :: any

local function snapEndpoint(): string
    return (string.gsub(_opts.endpoint or ENDPOINT, "/*$", "")) .. "/api/snap"
end
local _seenFingerprints: { [string]: number } = {}
local _autoCount = 0

--- Stable key for "the same message": kind + first line with numbers blanked.
function BugReportService.fingerprint(kind: string, message: string): string
    local first = string.match(message, "^[^\n]*") or message
    first = string.gsub(first, "%d+", "#")
    return kind .. ":" .. string.sub(first, 1, 200)
end

local function recentLog(limit: number): { string }
    local ok, history = pcall(function()
        return LogService:GetLogHistory()
    end)
    if not ok or type(history) ~= "table" then
        return {}
    end
    local out = {}
    local start = math.max(1, #history - limit + 1)
    for i = start, #history do
        local item = history[i]
        local tag = tostring(item.messageType):gsub("Enum%.MessageType%.", "")
        table.insert(out, string.format("[%s] %s", tag, tostring(item.message)))
    end
    return out
end

local function safeContext(): { [string]: any }
    local out: { [string]: any } = {}
    local function overlay(collect: (() -> { [string]: any })?)
        if not collect then
            return
        end
        local ok, ctx = pcall(collect)
        if ok and type(ctx) == "table" then
            for k, v in ctx do
                out[k] = v
            end
        elseif not ok then
            out.collectContextError = tostring(ctx)
        end
    end
    overlay(_opts.collectContext)
    overlay(_provider)
    return out
end

--- Extra server context from a script that holds state in locals. Independent of
--- start(): may be called before or after it. Overlays the BugloopContext module.
function BugReportService.setContextProvider(provider: (() -> { [string]: any })?)
    _provider = provider
end

--- Send a bug report from server code (or from the remote handler).
--- Returns (ok, idOrError). `extra` may carry source/fingerprint for automatic reports.
function BugReportService.report(
    note: string,
    clientContext: { [string]: any }?,
    playerName: string?,
    extra: { source: string?, fingerprint: string?, auto: { [string]: any }?, snap: string? }?
): (boolean, string)
    note = string.sub(tostring(note), 1, MAX_NOTE)
    local payload = {
        note = note,
        source = (extra and extra.source) or "roblox",
        fingerprint = extra and extra.fingerprint,
        snap = extra and extra.snap,
        -- no screenshot taken at F8 time: let the listener take one now (never for auto reports)
        screenshot = not (extra and (extra.snap or extra.auto)) and playerName ~= nil,
        project = _opts.project,
        context = {
            player = playerName,
            studio = RunService:IsStudio(),
            serverTime = os.time(),
            server = safeContext(),
            client = clientContext or {},
            auto = extra and extra.auto,
        },
        log = recentLog(_opts.logLines or 80),
    }
    local body = HttpService:JSONEncode(payload)

    local ok, result = pcall(function()
        return HttpService:PostAsync(_opts.endpoint or ENDPOINT, body, Enum.HttpContentType.ApplicationJson)
    end)
    if ok then
        local decoded = HttpService:JSONDecode(result)
        local id = tostring(decoded and decoded.id or "?")
        if decoded and decoded.duplicate then
            print(string.format("[BugReport] already known as %s (%s)", id, tostring(decoded.duplicate)))
        else
            print(string.format("[BugReport] sent %s: %s", id, string.sub(note, 1, 120)))
        end
        return true, id
    end

    warn(string.format("[BugReport] listener unreachable (%s); copy the line below into the inbox", tostring(result)))
    print("[BUGLOOP] " .. body)
    return false, tostring(result)
end

--------------------------------------------------------------------------------
-- Automatic capture of errors and warnings
--------------------------------------------------------------------------------

local function autoOptions(): AutoReportOptions?
    local a = _opts.autoReport
    if a == false then
        return nil
    end
    if type(a) == "table" then
        return a
    end
    return {}
end

local function isIgnored(message: string, auto: AutoReportOptions): boolean
    for _, pat in DEFAULT_IGNORE do
        if string.find(message, pat) then
            return true
        end
    end
    local ignore: { string } = auto.ignore or {}
    for _, pat in ignore do
        if string.find(message, pat) then
            return true
        end
    end
    return false
end

--- Report an error/warning seen on the server or forwarded from a client.
--- Deduped per play session by fingerprint; capped by maxPerSession.
function BugReportService.autoReport(kind: string, message: string, trace: string?, origin: string, playerName: string?)
    local auto = autoOptions()
    if not auto then
        return
    end
    if kind == "error" and auto.errors == false then
        return
    end
    if kind == "warning" and auto.warnings == false then
        return
    end
    if isIgnored(message, auto) then
        return
    end
    local fp = BugReportService.fingerprint(kind, message)
    if _seenFingerprints[fp] then
        _seenFingerprints[fp] += 1
        return
    end
    if _autoCount >= (auto.maxPerSession or 25) then
        return
    end
    _seenFingerprints[fp] = 1
    _autoCount += 1

    local note = string.format("AUTO %s (%s): %s", kind, origin, string.match(message, "^[^\n]*") or message)
    task.spawn(function()
        BugReportService.report(note, nil, playerName, {
            source = "roblox-auto",
            fingerprint = fp,
            auto = { kind = kind, origin = origin, message = message, trace = trace },
        })
    end)
end

local function hookServerOutput()
    local ScriptContext = game:GetService("ScriptContext")
    ScriptContext.Error:Connect(function(message: string, trace: string, _script: Instance?)
        BugReportService.autoReport("error", message, trace, "server")
    end)
    LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
        if messageType == Enum.MessageType.MessageWarning then
            BugReportService.autoReport("warning", message, nil, "server")
        end
    end)
end

function BugReportService.start(opts: StartOptions?)
    _opts = opts or {}
    if not RunService:IsStudio() and not _opts.enabledOutsideStudio then
        return
    end
    if autoOptions() then
        hookServerOutput()
    end

    local name = _opts.remoteName or REMOTE_NAME
    local parent: Instance = _opts.remoteParent or ReplicatedStorage
    local remote: Instance? = parent:FindFirstChild(name)
    if not remote and _opts.createRemote == false then
        remote = parent:WaitForChild(name, 30)
    end
    if not remote then
        local created = Instance.new("RemoteEvent")
        created.Name = name
        created.Parent = parent
        remote = created
    end
    local remoteEvent = remote :: RemoteEvent
    _remote = remoteEvent

    remoteEvent.OnServerEvent:Connect(function(player: Player, note: unknown, clientContext: unknown)
        if type(note) ~= "string" or #note == 0 then
            return
        end
        local ctx = if type(clientContext) == "table" then clientContext :: { [string]: any } else nil
        -- F8 was just pressed: have the listener screenshot the Studio window (it runs on
        -- this machine) and hold it for the report that follows.
        if ctx and ctx.__snap == true then
            _snaps[player] = nil
            task.spawn(function()
                local ok, result = pcall(function()
                    return HttpService:PostAsync(snapEndpoint(), "{}", Enum.HttpContentType.ApplicationJson)
                end)
                if ok then
                    local decoded = HttpService:JSONDecode(result)
                    if type(decoded) == "table" and type(decoded.snap) == "string" then
                        _snaps[player] = decoded.snap
                    end
                end
            end)
            return
        end
        -- Client-side automatic error/warning forwarded by BugReportClient
        local auto = ctx and ctx.__auto
        if type(auto) == "table" and type(auto.kind) == "string" and type(auto.message) == "string" then
            BugReportService.autoReport(auto.kind, auto.message, if type(auto.trace) == "string" then auto.trace else nil,
                "client:" .. player.Name, player.Name)
            return
        end
        local snap = _snaps[player]
        _snaps[player] = nil
        local ok, idOrErr = BugReportService.report(note, ctx, player.Name, { snap = snap })
        remoteEvent:FireClient(player, ok, idOrErr)
    end)

    print("[BugReport] ready (F8 in game; auto-capture " .. (if autoOptions() then "on" else "off") .. ")")
end

return BugReportService
