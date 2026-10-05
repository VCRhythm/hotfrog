--!strict
-- StarterPlayerScripts/Client/world/Bursts (ModuleScript)
-- Pooled one-shot particle bursts (tiny unanchored parts thrown by physics), the
-- shared engine behind the pebble debris (Effects), the Bubble pop / flame flare
-- (WorldScenery) and the lava splashes + surge embers (WorldLava). One
-- per-frame updater ages every live particle: it fades it out and returns it to
-- its pool when its life is up -- no TweenService tween per particle and no
-- delayed callbacks that could release a part twice or after it was re-acquired
-- (the old `task.delay(..., if part.Parent then release)` pattern).
--
-- ADAPTED from Unity ParticleSystems / Splash.cs / Pebble.cs: the parts are real
-- (client-owned) unanchored parts rather than a particle emitter, because that is
-- what the Pebble/Splash ports already were and it keeps their impulse + torque
-- feel. Never touches a server-owned part.

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpriteSkin = require(ReplicatedStorage.Shared.SpriteSkin)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Pool = require(script.Parent.Pool)

local Bursts = {}

export type Options = {
	name: string,
	size: Vector3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	sprite: string?, -- SkinAssets stem for a back-face Decal (nil = flat colour only)
	color: Color3?, -- default tint (a per-emit colour overrides it)
	cap: number?, -- max parked parts kept in the pool (default WorldConfig.BURST_POOL_CAP)
}

export type Spec = {
	count: number,
	lifetime: number,
	color: Color3?,
	-- Velocity: either a ring (`radialSpeed`, each particle 60..100% of it) or X/Y ranges.
	radialSpeed: number?,
	x: NumberRange?,
	y: NumberRange?,
	-- Torque opposing the X velocity (Pebble.cs rotForce = 2 * sign(xForce)).
	spin: number?,
	-- Random spawn offset half-range around `origin`.
	jitterX: number?,
	jitterY: number?,
	-- Fraction of the lifetime after which the fade starts (1 = no fade).
	fadeStart: number?,
	-- Uniform scale of the part for this burst (1 = Options.size).
	scale: number?,
}

type Live = { part: BasePart, decal: Decal?, born: number, life: number, fadeAt: number, release: (BasePart) -> () }

local live: { Live } = {}
local updater: RBXScriptConnection? = nil

local function update()
	local now = os.clock()
	for i = #live, 1, -1 do
		local p = live[i]
		local age = now - p.born
		if age >= p.life then
			p.release(p.part)
			live[i] = live[#live]
			live[#live] = nil
		elseif age > p.fadeAt then
			local t = (age - p.fadeAt) / math.max(1e-3, p.life - p.fadeAt)
			p.part.Transparency = t
			if p.decal then
				p.decal.Transparency = t
			end
		end
	end
	if #live == 0 and updater then
		updater:Disconnect()
		updater = nil
	end
end

function Bursts.new(options: Options)
	local pool = Pool.new(function(): BasePart
		local part = Instance.new("Part")
		part.Name = options.name
		part.Size = options.size
		if options.shape then
			part.Shape = options.shape
		end
		part.CanCollide = false
		part.CanQuery = false -- must never eat a tap meant for a step/bug
		part.CanTouch = false
		part.Material = options.material or Enum.Material.SmoothPlastic
		part.Color = options.color or Color3.new(1, 1, 1)
		if options.sprite then
			local decal = Instance.new("Decal")
			decal.Face = Enum.NormalId.Back -- +Z face: the one the camera (at +Z) sees
			decal:SetAttribute("Sprite", options.sprite)
			decal.Parent = part
			SpriteSkin.apply(part)
		end
		return part
	end, function(part: BasePart)
		part.Anchored = true
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		part.Transparency = 0
		part.Size = options.size
		part.Parent = nil
	end, {
		cap = options.cap or WorldConfig.BURST_POOL_CAP,
		dispose = function(part: BasePart)
			part:Destroy()
		end,
	})

	local burster = {}

	function burster.emit(origin: Vector3, spec: Spec)
		local fadeStart = spec.fadeStart or 0.5
		local now = os.clock()
		local size = if spec.scale then options.size * spec.scale else options.size
		for i = 1, spec.count do
			local part = pool.acquire()
			part.Size = size
			part.Color = spec.color or options.color or part.Color
			part.Transparency = 0
			local decal = part:FindFirstChildOfClass("Decal")
			if decal then
				decal.Transparency = 0
			end
			part.Anchored = false
			local jx = if spec.jitterX then (math.random() * 2 - 1) * spec.jitterX else 0
			local jy = if spec.jitterY then (math.random() * 2 - 1) * spec.jitterY else 0
			part.CFrame = CFrame.new(origin + Vector3.new(jx, jy, 0))
			local vx: number, vy: number
			if spec.radialSpeed then
				local angle = (i / spec.count) * math.pi * 2 + math.random() * 0.5
				local speed = spec.radialSpeed * (0.6 + math.random() * 0.4)
				vx, vy = math.cos(angle) * speed, math.sin(angle) * speed
			else
				local xr = spec.x or NumberRange.new(0, 0)
				local yr = spec.y or NumberRange.new(0, 0)
				vx = xr.Min + math.random() * (xr.Max - xr.Min)
				vy = yr.Min + math.random() * (yr.Max - yr.Min)
			end
			part.AssemblyLinearVelocity = Vector3.new(vx, vy, 0)
			if spec.spin then
				part.AssemblyAngularVelocity = Vector3.new(0, 0, -spec.spin * (if vx >= 0 then 1 else -1))
			end
			part.Parent = workspace
			table.insert(live, {
				part = part,
				decal = decal,
				born = now,
				life = spec.lifetime,
				fadeAt = spec.lifetime * fadeStart,
				release = pool.release,
			})
		end
		if not updater then
			-- per-frame visual: PreRender, so the fade lands in the frame it is drawn
			updater = RunService.PreRender:Connect(update)
		end
	end

	return burster
end

return Bursts
