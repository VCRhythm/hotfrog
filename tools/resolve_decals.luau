--!strict
-- tools/resolve_decals.luau — Studio-only fallback for turning Decal asset
-- ids into their underlying Image asset ids, for when the Open Cloud Asset
-- Delivery API path in tools/upload_to_roblox.py isn't available to you (no
-- legacy-asset:manage scope, endpoint down, etc.).
--
-- Why this is needed: uploading an image via the Open Cloud Assets API
-- creates a Decal that wraps the real Image asset, and the API returns the
-- Decal's id — which does NOT render when poked into Decal.Texture /
-- ImageLabel.Image from a script. Studio's InsertService, however, performs
-- the real decal->image resolution for you (this is exactly what happens
-- when you paste a decal id into a Texture property in the property editor),
-- so running this in Studio is a reliable fallback.
--
-- HOW TO USE:
--   1. Generate the id list (network-free):
--        python tools/upload_to_roblox.py --emit-studio-resolver
--      This prints (or writes, with --studio-resolver-out) a Lua array
--      literal like `{ 111, 222, 333 }` of every decal id still pending
--      resolution in tools/asset_ids.json.
--   2. Paste that literal over the `{}` on the `local DECAL_IDS = {}` line
--      below.
--   3. Open Studio (any place — this doesn't touch the DataModel besides a
--      transient InsertService:LoadAsset per id, each cleaned up after
--      reading it), open the Command Bar (View > Command Bar), paste this
--      whole file's contents in, and run it.
--   4. Copy the JSON printed to the Output window and save it as
--      tools/decal_image_ids.json in the repo.
--   5. Run: python tools/upload_to_roblox.py --resolve-only
--      This merges tools/decal_image_ids.json into tools/asset_ids.json
--      (no re-uploading), then python tools/write_asset_ids.py to fill in
--      SkinAssets.luau.

local DECAL_IDS: { number } = {}

local InsertService = game:GetService("InsertService")

local function findDecal(root: Instance): Decal?
	if root:IsA("Decal") then
		return root
	end
	for _, child in root:GetChildren() do
		local found = findDecal(child)
		if found then
			return found
		end
	end
	return nil
end

-- Texture is a `Content` value; tostring() on it yields the underlying uri —
-- either the modern "rbxassetid://<id>" or the legacy
-- "http://www.roblox.com/asset/?id=<id>" form.
local function imageIdFromTexture(texture: Content): number?
	local s = tostring(texture)
	local id = s:match("rbxassetid://(%d+)") or s:match("[?&]id=(%d+)")
	return id and tonumber(id) or nil
end

local results: { [string]: number | boolean } = {}

for _, decalId in DECAL_IDS do
	local ok, modelOrErr = pcall(function()
		return InsertService:LoadAsset(decalId)
	end)
	if ok then
		local model = modelOrErr :: Instance
		local decal = findDecal(model)
		local imageId = decal and imageIdFromTexture(decal.Texture)
		results[tostring(decalId)] = imageId or false
		if not imageId then
			warn(`resolve_decals: loaded asset {decalId} but found no Decal descendant with a resolvable Texture`)
		end
		model:Destroy()
	else
		results[tostring(decalId)] = false
		warn(`resolve_decals: InsertService:LoadAsset({decalId}) failed: {tostring(modelOrErr)}`)
	end
end

-- Hand-rolled JSON (avoids any HttpService availability/permission questions
-- in the command-bar context) — every key/value here is a plain number or
-- `false`, so no escaping is needed.
local lines = {}
for decalId, imageId in results do
	table.insert(lines, `\t"{decalId}": {if imageId then tostring(imageId) else "null"}`)
end
print("{\n" .. table.concat(lines, ",\n") .. "\n}")
