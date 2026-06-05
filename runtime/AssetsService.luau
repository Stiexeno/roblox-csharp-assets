-- AssetsService — tag-based asset registry. Looks up Instances
-- by CollectionService tags with two prefixes:
--
--   AssetKey:<name>    — exactly one Instance per name. Load() / LoadPrefab()
--                        throw if zero or two-or-more Instances share a key.
--   AssetLabel:<name>  — many Instances per name. LoadAll() / LoadAllPrefabs()
--                        return every match (empty list if none).
--
-- The prefixes are internal — user-facing API takes the bare name,
-- the service prepends. Keeps the tag namespace tidy and avoids
-- collisions with other tag users (Components, ad-hoc tags).

local CollectionService = game:GetService("CollectionService")

local KEY_PREFIX = "AssetKey:"
local LABEL_PREFIX = "AssetLabel:"

local AssetsService = setmetatable({}, {
	__tostring = function() return "AssetsService" end,
})
AssetsService.__index = AssetsService

function AssetsService.new(...)
	local self = setmetatable({}, AssetsService)
	return self:constructor(...) or self
end

AssetsService.__ctorParams = {}
AssetsService.__interfaces = { "IAssetsService" }

function AssetsService:constructor()
end

-- Strict single-Instance lookup by key. Three failure modes are
-- distinct error messages so debugging is straightforward.
function AssetsService:Load(key)
	local instance = self:_resolveSingleByKey(key)
	if not instance:IsA("ModuleScript") then
		error(string.format(
			"[Assets] Asset '%s' is a %s, not a ModuleScript. Use LoadPrefab() for non-ModuleScripts.",
			key, instance.ClassName), 2)
	end
	return require(instance)
end

-- Strict single-Instance lookup by key, expected to be a clone-able
-- Instance (Part, Model, Tool, GUI…). Skips ModuleScripts.
function AssetsService:LoadPrefab(key)
	local instance = self:_resolveSingleByKey(key)
	if instance:IsA("ModuleScript") then
		error(string.format(
			"[Assets] Asset '%s' is a ModuleScript. Use Load() instead.",
			key), 2)
	end
	return instance:Clone()
end

-- Permissive batch lookup by label. Empty result on no match — the
-- caller can detect emptiness without an exception, since "nothing
-- tagged with this label" is a valid state during early game setup.
function AssetsService:LoadAll(label)
	local tagged = CollectionService:GetTagged(LABEL_PREFIX .. label)
	local result = {}
	for _, instance in ipairs(tagged) do
		if instance:IsA("ModuleScript") then
			table.insert(result, require(instance))
		end
	end
	return result
end

function AssetsService:LoadAllPrefabs(label)
	local tagged = CollectionService:GetTagged(LABEL_PREFIX .. label)
	local result = {}
	for _, instance in ipairs(tagged) do
		if not instance:IsA("ModuleScript") then
			table.insert(result, instance:Clone())
		end
	end
	return result
end

function AssetsService:_resolveSingleByKey(key)
	local tagged = CollectionService:GetTagged(KEY_PREFIX .. key)
	if #tagged == 0 then
		error(string.format("[Assets] No asset tagged with key '%s'", key), 3)
	end
	if #tagged > 1 then
		local names = {}
		for _, inst in ipairs(tagged) do
			table.insert(names, inst:GetFullName())
		end
		error(string.format(
			"[Assets] %d Instances share AssetKey '%s': %s",
			#tagged, key, table.concat(names, ", ")), 3)
	end
	return tagged[1]
end

return AssetsService
