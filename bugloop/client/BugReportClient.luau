--!strict
--[[
    BugReportClient — client side of the bugloop capture (see ~/.claude/skills/bugloop).

    F8 opens a one-line text box. Enter sends the note plus client context to the
    server, which forwards it to the local bugloop listener. Escape cancels.

    Vendored by `bugloop.py init` into <repo>/bugloop/client and started by the
    Bugloop LocalScript next to it; no wiring in the game's own scripts. Do not edit
    the project copy: `bugloop.py upgrade` overwrites it. Settings live in ../Config.luau.

    Project context is optional, either of:
      * a ModuleScript named "BugloopClientContext" anywhere under PlayerScripts that
        returns a function returning a table (found by the Bugloop script), or
      * from any LocalScript that holds state in locals:
            BugReportClient.setContextProvider(function()
                return { selectedEntityId = selectedId }
            end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BugReportClient = {}

export type InitOptions = {
    key: Enum.KeyCode?,
    remoteName: string?,
    remoteParent: Instance?,  -- where the server put the RemoteEvent; default ReplicatedStorage
    enabledOutsideStudio: boolean?,
    collectContext: (() -> { [string]: any })?,
    autoReport: boolean?,  -- default true: forward client errors/warnings to the server
}

local _opts: InitOptions = {}
local _gui: ScreenGui? = nil
local _box: TextBox? = nil
local _status: TextLabel? = nil
local _remote: RemoteEvent? = nil
local _provider: (() -> { [string]: any })? = nil

local function buildGui(): (ScreenGui, TextBox, TextLabel)
    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name = "BugReportGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 1000
    gui.Enabled = false
    gui.IgnoreGuiInset = true

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 560, 0, 64)
    frame.Position = UDim2.new(0.5, -280, 0, 24)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -16, 0, 18)
    title.Position = UDim2.new(0, 8, 0, 4)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(200, 200, 210)
    title.TextSize = 13
    title.Font = Enum.Font.Gotham
    title.Text = "Bug report  (Enter = send, Esc = cancel)"
    title.Parent = frame

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -16, 0, 30)
    box.Position = UDim2.new(0, 8, 0, 26)
    box.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    box.BorderSizePixel = 0
    box.TextColor3 = Color3.new(1, 1, 1)
    box.PlaceholderText = "What went wrong?"
    box.TextSize = 15
    box.Font = Enum.Font.Gotham
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.Text = ""
    box.Parent = frame
    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = UDim.new(0, 6)
    boxCorner.Parent = box

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(0, 560, 0, 20)
    status.Position = UDim2.new(0.5, -280, 0, 92)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(160, 220, 160)
    status.TextSize = 13
    status.Font = Enum.Font.Gotham
    status.Text = ""
    status.Parent = gui

    gui.Parent = player:WaitForChild("PlayerGui")
    return gui, box, status
end

local function clientContext(): { [string]: any }
    local ctx: { [string]: any } = {}
    local cam = Workspace.CurrentCamera
    if cam then
        local p = cam.CFrame.Position
        ctx.camera = { x = math.floor(p.X), y = math.floor(p.Y), z = math.floor(p.Z) }
    end
    local mouse = Players.LocalPlayer:GetMouse()
    if mouse and mouse.Hit then
        local h = mouse.Hit.Position
        ctx.mouseHit = { x = math.floor(h.X), y = math.floor(h.Y), z = math.floor(h.Z) }
    end
    local function overlay(collect: (() -> { [string]: any })?)
        if not collect then
            return
        end
        local ok, extra = pcall(collect)
        if ok and type(extra) == "table" then
            for k, v in extra do
                ctx[k] = v
            end
        elseif not ok then
            ctx.collectContextError = tostring(extra)
        end
    end
    overlay(_opts.collectContext)
    overlay(_provider)
    return ctx
end

--- Extra client context from a script that holds state in locals. Independent of
--- init(): may be called before or after it. Overlays the BugloopClientContext module.
function BugReportClient.setContextProvider(provider: (() -> { [string]: any })?)
    _provider = provider
end

local function flash(text: string, seconds: number)
    local status = _status
    if not status then
        return
    end
    status.Text = text
    task.delay(seconds, function()
        if status.Text == text then
            status.Text = ""
        end
    end)
end

local function close()
    if _gui then
        _gui.Enabled = false
    end
    if _box then
        _box:ReleaseFocus()
    end
end

local function open()
    local gui, box = _gui, _box
    if not gui or not box then
        return
    end
    -- Ask the listener (via the server) to screenshot the Studio window now, while the
    -- screen still shows what the report is about; the report that follows carries it.
    if _remote then
        _remote:FireServer("snap", { __snap = true })
    end
    gui.Enabled = true
    box.Text = ""
    task.defer(function()
        box:CaptureFocus()
    end)
end

function BugReportClient.init(opts: InitOptions?)
    _opts = opts or {}
    if not RunService:IsStudio() and not _opts.enabledOutsideStudio then
        return
    end

    local gui, box, status = buildGui()
    _gui, _box, _status = gui, box, status
    local key = _opts.key or Enum.KeyCode.F8

    local remote = (_opts.remoteParent or ReplicatedStorage):WaitForChild(_opts.remoteName or "BugReport", 10)
    if remote and remote:IsA("RemoteEvent") then
        _remote = remote
        remote.OnClientEvent:Connect(function(ok: boolean, idOrErr: string)
            flash(if ok then ("sent " .. tostring(idOrErr)) else ("FAILED: " .. tostring(idOrErr) .. " (see server output)"), 3)
        end)
    end

    box.FocusLost:Connect(function(enterPressed: boolean)
        if not gui.Enabled then
            return
        end
        local note = box.Text
        close()
        if enterPressed and #note > 0 then
            if _remote then
                _remote:FireServer(note, clientContext())
                flash("sending...", 3)
            else
                flash("no BugReport remote on server", 3)
            end
        end
    end)

    UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
        if input.KeyCode == key and not gui.Enabled then
            open()
        elseif input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
            close()
        end
    end)

    -- Forward client-side errors and warnings to the server, which dedupes and files them.
    if _opts.autoReport ~= false then
        local seen: { [string]: boolean } = {}
        local sent = 0
        local function forward(kind: string, message: string, trace: string?)
            local first = string.gsub(string.match(message, "^[^\n]*") or message, "%d+", "#")
            local key = kind .. ":" .. first
            if seen[key] or sent >= 25 or string.find(message, "^%[BugReport%]") then
                return
            end
            seen[key] = true
            sent += 1
            if _remote then
                _remote:FireServer("auto", { __auto = { kind = kind, message = message, trace = trace } })
            end
        end
        game:GetService("ScriptContext").Error:Connect(function(message: string, trace: string, _script: Instance?)
            forward("error", message, trace)
        end)
        game:GetService("LogService").MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
            if messageType == Enum.MessageType.MessageWarning then
                forward("warning", message, nil)
            end
        end)
    end
end

return BugReportClient
