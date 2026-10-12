--!strict
-- ServerScriptService/Server/Chef (ModuleScript)
-- The Kitchen's Chef as a hazard (owner's ruling b-20261012-141130-fhme, doc
-- 17): Unity's Chef is only drifting scenery. Here each lane's Chef, on the
-- Kitchen level only, picks one visible step its player isn't holding every
-- Config.CHEF_INTERVAL_MIN..MAX seconds and, after a readable tell, does one of:
--   Knife -- walks over, raises the knife (the tell), chops: the step drops away
--   Food  -- winds back a potato (the tell), throws it: the step is knocked loose
--   Shove -- walks over, sets his hands (the tell), shoves: the step slides sideways
-- If the player grabs the target (or it leaves the lane or the view) before the
-- blow lands, the action fizzles -- the held step is never hit. The blow is
-- shown Config.CHEF_STRIKE_GRACE before it is applied, so a grab already on its
-- way when the player saw it still saves the step. Knife and Food only take a
-- step while another un-held foothold is left in view (in Normal mode nothing
-- spawns until the player grabs, so cutting the last one would strand them),
-- and a Shove only lands on a spot clear of every other step (Lane.clearSpot's
-- spacing) and of the PlayerList keep-out.
--
-- Pure per-lane timing and targeting; GameServer drives `tick` from its step
-- Heartbeat and applies the effect through `strike` (ctx.dropAway / a slide).
-- Client contract (WorldChef.client.luau, cosmetic only): the lane folder's
-- `ChefAction` ("Knife" | "Food" | "Shove" | nil), `ChefPhase` ("Walk" |
-- "WindUp" | "Flight" | "Strike"), `ChefSeq` (bumped per action) and
-- `ChefShoveDir` (+1 / -1, Shove only), plus `ChefTarget = true` on the
-- targeted step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Levels = require(ReplicatedStorage.Shared.Levels)
local StepKinds = require(ReplicatedStorage.Shared.StepKinds)
local Lane = require(script.Parent.Lane)

local Chef = {}

export type Action = "Knife" | "Food" | "Shove"
type IsHeld = (lane: Lane.Lane, step: BasePart) -> boolean
type Strike = (lane: Lane.Lane, step: BasePart, st: Lane.StepState, action: Action, shoveDir: number) -> ()
type Phase = "Idle" | "Walk" | "WindUp" | "Flight" | "Strike"

type ChefState = {
	phase: Phase,
	timer: number, -- seconds left in this phase (Idle: until the next action)
	action: Action?,
	target: BasePart?,
	targetState: Lane.StepState?, -- the target's generation (lane.states[target] == targetState)
	shoveDir: number,
	pending: boolean, -- Strike shown, effect not yet applied (CHEF_STRIKE_GRACE)
	seq: number,
}

local states: { [Lane.Lane]: ChefState } = setmetatable({}, { __mode = "k" }) :: any
local rng = Random.new()

local function interval(): number
	return rng:NextNumber(Config.CHEF_INTERVAL_MIN, Config.CHEF_INTERVAL_MAX)
end

-- First action on a fresh Kitchen: after the Pot -> Kitchen arrival beat.
local function firstDelay(): number
	return Config.CLASSIC_ARRIVAL_HOLD_TIME + interval()
end

local function setPhase(lane: Lane.Lane, s: ChefState, phase: Phase, time: number)
	s.phase = phase
	s.timer = time
	lane.folder:SetAttribute("ChefPhase", if phase == "Idle" then nil else phase)
end

-- End the current action (done or fizzled) and go back to wandering.
local function finish(lane: Lane.Lane, s: ChefState, nextIn: number)
	local target = s.target
	if target and lane.states[target] == s.targetState then
		target:SetAttribute("ChefTarget", nil)
	end
	s.action = nil
	s.target = nil
	s.targetState = nil
	s.pending = false
	lane.folder:SetAttribute("ChefAction", nil)
	lane.folder:SetAttribute("ChefShoveDir", nil)
	setPhase(lane, s, "Idle", nextIn)
end

local function stateOf(lane: Lane.Lane): ChefState
	local s = states[lane]
	if not s then
		s = { phase = "Idle", timer = firstDelay(), shoveDir = 1, pending = false, seq = 0 }
		states[lane] = s
	end
	return s
end

-- Is `pos` inside the camera band, `margin` studs in from its top and bottom?
-- (The width is the server's assumed one, Config.SPAWN_VIEW_HALF_WIDTH.)
local function inView(lane: Lane.Lane, pos: Vector3, margin: number): boolean
	local rel = pos - lane.origin
	return math.abs(rel.Y) < Config.VIEW_HALF_HEIGHT - margin and math.abs(rel.X) < Config.SPAWN_VIEW_HALF_WIDTH
end

-- A step the Chef may pick: live, not held, not already dropping, a plain
-- foothold (not the pot's rim or a direction arrow), and inside the view.
local function eligible(lane: Lane.Lane, step: BasePart, st: Lane.StepState, isHeld: IsHeld): boolean
	if st.dropElapsed or isHeld(lane, step) then
		return false
	end
	local kindName = step:GetAttribute("KindName")
	if kindName == Lane.POT_RIM_KIND then
		return false
	end
	local kind = if typeof(kindName) == "string" then StepKinds[kindName] else nil
	if kind and kind.isArrow then
		return false
	end
	return inView(lane, st.base, Config.CHEF_TARGET_MARGIN)
end

-- Would the player still have somewhere to go without `target`: another live,
-- un-held, non-dropping step in view (any kind -- the rim and arrows count)?
local function otherFoothold(lane: Lane.Lane, target: BasePart, isHeld: IsHeld): boolean
	for step, st in lane.states do
		if step ~= target and not st.dropElapsed and not isHeld(lane, step) and inView(lane, st.base, 0) then
			return true
		end
	end
	return false
end

local function hitOf(step: BasePart): Vector2
	return (step:GetAttribute("HitSize") :: Vector2?) or Vector2.new(step.Size.X, step.Size.Y)
end

-- Can `step` be shoved CHEF_SHOVE_DISTANCE along `dir` (+1/-1)? Its resting
-- spot must stay in view, keep Lane.clearSpot's spacing (grab boxes, sweeps,
-- SPAWN_GAP) from every other live step -- the held one included -- and, while
-- the lane isn't drifting, stay out of the PlayerList keep-out (clearSpot's
-- own obstruction rule).
local function shoveClear(lane: Lane.Lane, step: BasePart, st: Lane.StepState, dir: number): boolean
	local shared = lane:sharedPending()
	local dest = lane:restPosition(step, shared) + Vector3.new(dir * Config.CHEF_SHOVE_DISTANCE, 0, 0)
	if not inView(lane, dest, 0) then
		return false
	end
	local hit = hitOf(step)
	local hitOffset = (step:GetAttribute("HitOffset") :: Vector2?) or Vector2.zero
	if not lane:drifts() and lane:obstructs(dest, hit, hitOffset) then
		return false
	end
	return not lane:crowdsSpot(dest, hit, st.sweep, shared, step)
end

-- `preferred` if that way is clear, else the other way, else nil.
local function shoveDirFor(lane: Lane.Lane, step: BasePart, st: Lane.StepState, preferred: number): number?
	if shoveClear(lane, step, st, preferred) then
		return preferred
	elseif shoveClear(lane, step, st, -preferred) then
		return -preferred
	end
	return nil
end

-- Stop whatever the Chef is doing on `lane` (left the Kitchen, died, menu, a
-- frog not yet armed): clear the client contract and restart the countdown
-- from the arrival beat.
function Chef.reset(lane: Lane.Lane)
	local s = states[lane]
	if not s then
		return
	end
	if s.action then
		finish(lane, s, 0)
	end
	s.timer = firstDelay()
end

-- Pick a target and an action for it; false when nothing in view will do.
local function begin(lane: Lane.Lane, s: ChefState, isHeld: IsHeld): boolean
	local candidates: { BasePart } = {}
	for step, st in lane.states do
		if eligible(lane, step, st, isHeld) then
			table.insert(candidates, step)
		end
	end
	if #candidates == 0 then
		return false
	end
	local step = candidates[rng:NextInteger(1, #candidates)]
	local st = lane.states[step]
	local options: { Action } = {}
	if otherFoothold(lane, step, isHeld) then
		table.insert(options, "Knife" :: Action)
		table.insert(options, "Food" :: Action)
	end
	local dir = shoveDirFor(lane, step, st, if rng:NextNumber() < 0.5 then -1 else 1)
	if dir then
		table.insert(options, "Shove" :: Action)
	end
	if #options == 0 then
		return false
	end
	local action: Action = options[rng:NextInteger(1, #options)]
	s.action = action
	s.target = step
	s.targetState = st
	s.shoveDir = dir or 1
	s.pending = false
	s.seq += 1
	step:SetAttribute("ChefTarget", true)
	lane.folder:SetAttribute("ChefShoveDir", if action == "Shove" then s.shoveDir else nil)
	lane.folder:SetAttribute("ChefSeq", s.seq)
	lane.folder:SetAttribute("ChefAction", action)
	if action == "Food" then
		setPhase(lane, s, "WindUp", Config.CHEF_WINDUP_TIME) -- thrown from where he stands
	else
		setPhase(lane, s, "Walk", Config.CHEF_WALK_TIME)
	end
	return true
end

-- The grace after the shown blow is over: land it if it is still fair. The
-- view and the other footholds are re-checked (a pull during the tell can
-- change both). A shove keeps the direction its arrow showed: if that side is
-- no longer clear the shove is called off rather than going against the tell.
local function land(lane: Lane.Lane, s: ChefState, isHeld: IsHeld, strike: Strike): boolean
	local action, target, st = s.action, s.target, s.targetState
	if not action or not target or not st or not inView(lane, st.base, 0) then
		return false
	end
	if action == "Shove" then
		if not shoveClear(lane, target, st, s.shoveDir) then
			return false
		end
	elseif not otherFoothold(lane, target, isHeld) then
		return false
	end
	strike(lane, target, st, action :: Action, s.shoveDir)
	return true
end

-- One server tick for `lane`. `active` is the caller's gate (Playing, frog
-- armed and alive); the Kitchen check is made here. `strike` applies the
-- effect to a still-live, un-held target.
-- `speed` (optional, default 1) is the Normal-mode streak speed-up
-- (b-20261010-192608-4bs3 ruling 8zmn): it shortens every wait except the Strike
-- phase, so CHEF_STRIKE_GRACE (the fairness window) is never shortened.
function Chef.tick(lane: Lane.Lane, dt: number, active: boolean, isHeld: IsHeld, strike: Strike, speed: number?)
	if not active or lane.levelIndex ~= Levels.KITCHEN then
		Chef.reset(lane)
		return
	end
	local s = stateOf(lane)

	-- Until the effect is applied the target must stay the same live step,
	-- un-held and not already dropping; otherwise the action fizzles.
	if s.action and (s.phase ~= "Strike" or s.pending) then
		local target, targetState = s.target, s.targetState
		if
			not target
			or not targetState
			or lane.states[target] ~= targetState
			or targetState.dropElapsed
			or isHeld(lane, target)
		then
			finish(lane, s, interval()) -- a fizzle still counts as his action
			return
		end
	end

	s.timer -= if s.phase == "Strike" then dt else dt * (speed or 1)
	if s.timer > 0 then
		return
	end

	if s.phase == "Idle" then
		if not begin(lane, s, isHeld) then
			s.timer = Config.CHEF_RETRY_TIME
		end
	elseif s.phase == "Walk" then
		setPhase(lane, s, "WindUp", Config.CHEF_WINDUP_TIME)
	elseif s.phase == "WindUp" and s.action == "Food" then
		setPhase(lane, s, "Flight", Config.CHEF_FOOD_FLIGHT_TIME)
	elseif s.phase == "WindUp" or s.phase == "Flight" then
		s.pending = true
		setPhase(lane, s, "Strike", Config.CHEF_STRIKE_GRACE)
	elseif s.pending then
		s.pending = false
		if land(lane, s, isHeld, strike) then
			s.timer = math.max(Config.CHEF_STRIKE_TIME - Config.CHEF_STRIKE_GRACE, 0)
		else
			finish(lane, s, interval())
		end
	else -- Strike follow-through over
		finish(lane, s, interval())
	end
end

return Chef
