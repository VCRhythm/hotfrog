--!strict
-- StarterPlayerScripts/Client/StudioBot (LocalScript)
-- Studio-only climbing bot for playtests driven through the Studio MCP
-- (b-20261020-213324-txe8), so a check needn't write its own bot each time. It
-- fires the real GrabStep / ReleaseStep remotes, hand over hand, exactly as a
-- player's taps would (the server validates them as usual). Never created
-- outside Studio. Pairs with the server's ServerStorage/StudioSkipTo.
--
-- Driven through a BindableFunction under the LocalPlayer, so execute_luau in
-- the Client datamodel reaches this live script:
--   local bot = game.Players.LocalPlayer.StudioBot
--   bot:Invoke("start", { steps = 5, mode = "Normal", interval = 0.7, restart = false })
--   bot:Invoke("wait", 40)   -- blocks <= 45 s until the bot stops; returns the status line
--   bot:Invoke("status")     -- one-line stats: grabs, rejects, deaths, levels, score
--   bot:Invoke("stop")
-- A Menu lane is started first (StartRun with `mode`, default Normal).
-- Target pick (the filter earlier checks found works for every travel direction):
-- own-lane steps within 29 studs of the lane origin (server reach), not held or
-- grabbed in the last few grabs (matched by the step's spawn `Gen` too: steps are
-- pooled, so a recycled Instance is a new step -- b-20261020-220122-w9qy); the
-- pot's rim first; then, within |x| < 24 and
-- -2 < y < 26, the nearest step at least CLIMB_Y up (a grab pulls it to the
-- centre, so low steps barely scroll and an upstream rim would never arrive),
-- else the nearest; else the nearest step in reach at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local GrabStep = remotes:WaitForChild("GrabStep") :: RemoteEvent
local ReleaseStep = remotes:WaitForChild("ReleaseStep") :: RemoteEvent
local StartRun = remotes:WaitForChild("StartRun") :: RemoteEvent
local ForceRelease = remotes:WaitForChild("ForceRelease") :: RemoteEvent
local playField = workspace:WaitForChild("PlayField")
local stepsFolder = playField:WaitForChild("Steps")
local lanesFolder = playField:WaitForChild("Lanes")

local MAX_X, MIN_Y, MAX_Y, MAX_DIST = 24, -2, 26, 29
local CLIMB_Y = 3 -- prefer steps at least this far above the origin: their pulls scroll the level on
local RECENT = 6 -- grabs before a step may be picked again
local CONFIRM_TIME = 0.6 -- seconds to wait for the server to count a grab
local MAX_STALL = 10 -- seconds with nothing to grab before giving up

type Stats = {
	running: boolean,
	target: number,
	grabs: number,
	rejects: number,
	deaths: number,
	stalls: number,
	levels: { string },
	score: number,
	runSteps: number,
	stopReason: string,
	started: number,
	ended: number?,
}

local stats: Stats = {
	running = false,
	target = 0,
	grabs = 0,
	rejects = 0,
	deaths = 0,
	stalls = 0,
	levels = {},
	score = 0,
	runSteps = 0,
	stopReason = "never started",
	started = os.clock(),
	ended = nil,
}
local generation = 0 -- bumped by start/stop; a loop from an older start exits
local held: { [number]: BasePart } = {}

-- A recently grabbed step: the pooled Instance plus its spawn generation, so a
-- recycled Instance (a fresh step) is not mistaken for the one grabbed before.
type Recent = { step: BasePart, gen: any }

local function isRecent(recent: { Recent }, step: BasePart): boolean
	local gen = step:GetAttribute("Gen")
	for _, entry in recent do
		if entry.step == step and entry.gen == gen then
			return true
		end
	end
	return false
end

local function laneFolder(): Instance?
	return lanesFolder:FindFirstChild(tostring(player.UserId))
end

local function attr(name: string): any
	local folder = laneFolder()
	return if folder then folder:GetAttribute(name) else nil
end

local function runSteps(): number
	local v = player:GetAttribute("RunSteps")
	return if typeof(v) == "number" then v else 0
end

local function refreshScore()
	local ls = player:FindFirstChild("leaderstats")
	local score = ls and ls:FindFirstChild("Score")
	stats.score = if score and score:IsA("IntValue") then score.Value else 0
	stats.runSteps = runSteps()
end

local function statusLine(): string
	refreshScore()
	local elapsed = (stats.ended or os.clock()) - stats.started
	return ("%s %d/%d grabs, %d rejects, %d deaths, %d stalls | levels %s | now %s %s | score %d runSteps %d | %.1fs%s"):format(
		if stats.running then "RUNNING" else "STOPPED",
		stats.grabs,
		stats.target,
		stats.rejects,
		stats.deaths,
		stats.stalls,
		table.concat(stats.levels, ">"),
		tostring(attr("Level")),
		tostring(attr("RunState")),
		stats.score,
		stats.runSteps,
		elapsed,
		if stats.running then "" else " (" .. stats.stopReason .. ")"
	)
end

local function pickStep(origin: Vector3, recent: { Recent }): BasePart?
	local best: BasePart? = nil
	local high: BasePart? = nil
	local loose: BasePart? = nil
	local bestDist, highDist, looseDist = math.huge, math.huge, math.huge
	for _, child in stepsFolder:GetChildren() do
		if not child:IsA("BasePart") or child:GetAttribute("LaneUserId") ~= player.UserId then
			continue
		end
		if held[1] == child or held[2] == child or isRecent(recent, child) then
			continue
		end
		local rel = child.Position - origin
		local dist = Vector2.new(rel.X, rel.Y).Magnitude
		if dist >= MAX_DIST then
			continue -- past the server's reach check
		end
		if child:GetAttribute("KindName") == "PotRim" then
			return child
		end
		if math.abs(rel.X) >= MAX_X or rel.Y <= MIN_Y or rel.Y >= MAX_Y then
			-- in reach but off the usual box (e.g. the pot's last steps sinking
			-- below while its rim still drifts in): only when nothing better is left
			if dist < looseDist then
				loose, looseDist = child, dist
			end
			continue
		end
		if dist < bestDist then
			best, bestDist = child, dist
		end
		if rel.Y >= CLIMB_Y and dist < highDist then
			high, highDist = child, dist
		end
	end
	return high or best or loose
end

local function waitForState(want: string, timeout: number, gen: number): boolean
	local deadline = os.clock() + timeout
	while attr("RunState") ~= want do
		if os.clock() > deadline or gen ~= generation then
			return false
		end
		task.wait(0.1)
	end
	return true
end

local function stop(reason: string)
	stats.running = false
	stats.stopReason = reason
	stats.ended = os.clock()
	refreshScore()
end

local function run(gen: number, mode: string, interval: number, restart: boolean)
	local recent: { Recent } = {}
	local stalledSince: number? = nil
	local limb = 1
	while gen == generation and stats.grabs < stats.target do
		local state = attr("RunState")
		if state ~= "Playing" then
			table.clear(held)
			if state == "Menu" then
				StartRun:FireServer(mode)
				if not waitForState("Playing", 5, gen) then
					stop("StartRun did not start a run")
					return
				end
			elseif state == "Dead" then
				stats.deaths += 1
				if not restart then
					stop("frog died")
					return
				end
				if not waitForState("Menu", 15, gen) then
					stop("stuck in Dead")
					return
				end
			else
				stop("no lane / unknown run state " .. tostring(state))
				return
			end
			continue
		end

		local origin = attr("Origin")
		local step = if typeof(origin) == "Vector3" then pickStep(origin, recent) else nil
		if not step then
			stats.stalls += 1
			stalledSince = stalledSince or os.clock()
			if os.clock() - (stalledSince :: number) > MAX_STALL then
				stop("nothing to grab for " .. MAX_STALL .. "s")
				return
			end
			task.wait(0.25)
			continue
		end
		stalledSince = nil

		local old = held[limb]
		if old then
			ReleaseStep:FireServer(limb, old)
			held[limb] = nil
		end
		local before = runSteps()
		GrabStep:FireServer(step, step.Position, limb)
		held[limb] = step
		table.insert(recent, { step = step, gen = step:GetAttribute("Gen") })
		if #recent > RECENT then
			table.remove(recent, 1)
		end
		local deadline = os.clock() + CONFIRM_TIME
		while runSteps() == before and os.clock() < deadline and attr("RunState") == "Playing" do
			task.wait()
		end
		if runSteps() > before then
			stats.grabs += 1
			limb = 3 - limb
		else
			stats.rejects += 1
			held[limb] = nil
		end
		task.wait(interval)
	end
	if gen == generation then
		stop(if stats.grabs >= stats.target then "done" else "stopped")
	end
end

ForceRelease.OnClientEvent:Connect(function(step)
	for i = 1, 2 do
		if held[i] == step then
			held[i] = nil
		end
	end
end)

-- Record every level the lane passes through while the bot runs.
local function watchLevel(folder: Instance)
	folder:GetAttributeChangedSignal("Level"):Connect(function()
		local level = folder:GetAttribute("Level")
		if stats.running and typeof(level) == "string" then
			table.insert(stats.levels, level)
		end
	end)
end
local existing = laneFolder()
if existing then
	watchLevel(existing)
end
lanesFolder.ChildAdded:Connect(function(child)
	if child.Name == tostring(player.UserId) then
		watchLevel(child)
	end
end)

local fn = Instance.new("BindableFunction")
fn.Name = "StudioBot"
fn.OnInvoke = function(command: any, arg: any): string
	if command == "start" then
		local opts = if type(arg) == "table" then arg else {}
		generation += 1
		table.clear(held)
		stats.running = true
		stats.target = if type(opts.steps) == "number" then opts.steps else 10
		stats.grabs, stats.rejects, stats.deaths, stats.stalls = 0, 0, 0, 0
		local level = attr("Level")
		stats.levels = { if typeof(level) == "string" then level else "?" }
		stats.started = os.clock()
		stats.ended = nil
		stats.stopReason = ""
		local mode = if type(opts.mode) == "string" then opts.mode else "Normal"
		local interval = if type(opts.interval) == "number" then opts.interval else 0.7
		task.spawn(run, generation, mode, interval, opts.restart == true)
		return "started: " .. statusLine()
	elseif command == "wait" then
		local deadline = os.clock() + math.clamp(if type(arg) == "number" then arg else 40, 0, 45)
		while stats.running and os.clock() < deadline do
			task.wait(0.2)
		end
		return statusLine()
	elseif command == "stop" then
		generation += 1
		if stats.running then
			stop("stopped by caller")
		end
		return statusLine()
	end
	return statusLine()
end
fn.Parent = player
