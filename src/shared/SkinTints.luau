--!strict
-- ReplicatedStorage/Shared/SkinTints (ModuleScript)
-- Skin colourways (b-20261008-142125-1ucz; not in Unity -- see doc 17): a Fly
-- sink once every skin is bought. One shared list of tints, bought PER SKIN
-- (owning Mint on Blue Frog doesn't give it to Hot Frog), no new art: a tint is
-- a Color3 multiplied over the frog's sprite decals.
--
-- Kept out of SkinCatalog on purpose: that module is iterated with
-- `pairs(Catalog)` as a numeric id -> skin map (Profiles, SkinService, StoreUI),
-- so a string `Tints` key there would break those loops.
--
--   id 0 = no tint (white, the art as drawn); always "owned".
--   Profile: ownedTints[SkinTints.key(skinId, tintId)] = true,
--            selectedTints[tostring(skinId)] = tintId (string keys: these tables
--            go through DataStore JSON and RemoteEvents untouched).
--   Replication: SkinService sets the player's `FrogTint` attribute to the tint
--   id worn on the selected skin; WorldFrogCosmetics tints that frog for every
--   viewer.

export type Tint = { id: number, name: string, color: Color3, flyCost: number }

local SkinTints = {}

SkinTints.list = {
	{ id = 1, name = "Mint", color = Color3.fromRGB(150, 255, 190), flyCost = 400 },
	{ id = 2, name = "Berry", color = Color3.fromRGB(255, 150, 210), flyCost = 600 },
	{ id = 3, name = "Midnight", color = Color3.fromRGB(130, 140, 255), flyCost = 800 },
	{ id = 4, name = "Gold", color = Color3.fromRGB(255, 215, 80), flyCost = 1500 },
} :: { Tint }

SkinTints.NONE = Color3.new(1, 1, 1)

-- Eye parts keep their own colours so a tinted frog still has white eyes; the
-- Accessory (sunglasses, helmet) is gear, not frog skin, so it keeps its own too.
local UNTINTED: { [string]: boolean } = {
	LeftSclera = true,
	RightSclera = true,
	LeftEye = true,
	RightEye = true,
	LeftPupil = true,
	RightPupil = true,
	Accessory = true,
}

local byId: { [number]: Tint } = {}
for _, tint in SkinTints.list do
	byId[tint.id] = tint
end

function SkinTints.get(id: any): Tint?
	return if type(id) == "number" then byId[id] else nil
end

function SkinTints.key(skinId: number, tintId: number): string
	return skinId .. ":" .. tintId
end

-- The Color3 for a tint id (white for 0 / unknown).
function SkinTints.color(id: any): Color3
	local tint = SkinTints.get(id)
	return if tint then tint.color else SkinTints.NONE
end

-- Is this sprite instance part of the tinted skin (a frog `Suffix` sprite that
-- isn't an eye)?
function SkinTints.isTinted(obj: Instance): boolean
	local suffix = obj:GetAttribute("Suffix")
	return typeof(suffix) == "string" and not UNTINTED[suffix]
end

-- Multiply `color` over every tintable frog sprite under `root` (Decal/Texture
-- Color3, ImageLabel/ImageButton ImageColor3). Local visual property only.
function SkinTints.apply(root: Instance, color: Color3)
	for _, obj in root:GetDescendants() do
		if SkinTints.isTinted(obj) then
			if obj:IsA("Decal") then
				obj.Color3 = color -- Texture inherits from Decal
			elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
				local ui = obj :: any
				ui.ImageColor3 = color
			end
		end
	end
end

return SkinTints
