local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResourceManager = {}

-- NEW CANONICAL STANDARD:
-- HP_cur / HP_max / HP_reg
-- Fuel_cur / Fuel_max / Fuel_reg
-- Cargo_cur / Cargo_max / Cargo_reg
-- Ammo_cur / Ammo_max / Ammo_reg
--
-- Old attributes are mirrored temporarily so the existing vehicle,
-- warehouse, projectile and HUD code keeps working during migration.

local RESOURCES = {
	HP = {
		cur = "HP_cur",
		max = "HP_max",
		reg = "HP_reg",
		oldCur = {"Current_health", "Health"},
		oldMax = {"Max_health", "MaxHealth"},
	},
	Fuel = {
		cur = "Fuel_cur",
		max = "Fuel_max",
		reg = "Fuel_reg",
		oldCur = {"Current_fuel", "Fuel_current", "CurrentFuel", "Fuel"},
		oldMax = {"Max_fuel", "Fuel_max", "MaxFuel", "Fuel_capacity", "FuelCapacity"},
	},
	Cargo = {
		cur = "Cargo_cur",
		max = "Cargo_max",
		reg = "Cargo_reg",
		oldCur = {"Current_cargo", "Cargo_current", "Loaded_cargo", "Cargo", "CurrentCargo"},
		oldMax = {"Max_cargo", "Cargo_max", "Cargo_capacity", "MaxCargo"},
	},
	Ammo = {
		cur = "Ammo_cur",
		max = "Ammo_max",
		reg = "Ammo_reg",
		oldCur = {"Current_ammo", "Rocket_current"},
		oldMax = {"Magazine_size", "Max_ammo", "Rocket_max"},
	},
}

local watched = setmetatable({}, {__mode = "k"})
local internalWrite = setmetatable({}, {__mode = "k"})
local started = false

local function numberAttr(object, name)
	local value = object:GetAttribute(name)
	if value == nil then
		return nil
	end
	return tonumber(value)
end

local function firstNumber(object, names)
	for _, name in ipairs(names) do
		local value = numberAttr(object, name)
		if value ~= nil then
			return value
		end
	end
	return nil
end

local function safeSet(object, name, value)
	if object:GetAttribute(name) == value then
		return
	end

	internalWrite[object] = true
	object:SetAttribute(name, value)
	internalWrite[object] = nil
end

local function resourceExists(object, def)
	if object:GetAttribute(def.cur) ~= nil
		or object:GetAttribute(def.max) ~= nil
		or firstNumber(object, def.oldCur) ~= nil
		or firstNumber(object, def.oldMax) ~= nil
	then
		return true
	end
	return false
end

local function initializeResource(object, def)
	if not resourceExists(object, def) then
		return
	end

	local maxValue = numberAttr(object, def.max)
	if maxValue == nil then
		maxValue = firstNumber(object, def.oldMax)
	end

	local currentValue = numberAttr(object, def.cur)
	if currentValue == nil then
		currentValue = firstNumber(object, def.oldCur)
	end

	if maxValue == nil and currentValue ~= nil then
		maxValue = currentValue
	end
	if currentValue == nil and maxValue ~= nil then
		currentValue = maxValue
	end

	maxValue = math.max(0, maxValue or 0)
	currentValue = math.clamp(currentValue or 0, 0, maxValue)

	safeSet(object, def.max, maxValue)
	safeSet(object, def.cur, currentValue)

	if object:GetAttribute(def.reg) == nil then
		safeSet(object, def.reg, 0)
	end

	-- Compatibility aliases. These can be removed after all old systems
	-- have been converted to the canonical attributes.
	for _, oldName in ipairs(def.oldMax) do
		if oldName ~= def.max then
			safeSet(object, oldName, maxValue)
		end
	end
	for _, oldName in ipairs(def.oldCur) do
		if oldName ~= def.cur then
			safeSet(object, oldName, currentValue)
		end
	end
end

local function syncFromCanonical(object, def, kind)
	if internalWrite[object] then
		return
	end

	if kind == "cur" then
		local maxValue = numberAttr(object, def.max) or 0
		local value = math.clamp(numberAttr(object, def.cur) or 0, 0, maxValue)
		safeSet(object, def.cur, value)

		for _, oldName in ipairs(def.oldCur) do
			if oldName ~= def.cur then
				safeSet(object, oldName, value)
			end
		end
	elseif kind == "max" then
		local value = math.max(0, numberAttr(object, def.max) or 0)
		safeSet(object, def.max, value)

		for _, oldName in ipairs(def.oldMax) do
			if oldName ~= def.max then
				safeSet(object, oldName, value)
			end
		end

		local current = numberAttr(object, def.cur)
		if current ~= nil and current > value then
			safeSet(object, def.cur, value)
			for _, oldName in ipairs(def.oldCur) do
				if oldName ~= def.cur then
					safeSet(object, oldName, value)
				end
			end
		end
	end
end

local function syncFromLegacy(object, def, oldName, kind)
	if internalWrite[object] then
		return
	end

	local value = numberAttr(object, oldName)
	if value == nil then
		return
	end

	if kind == "cur" then
		local maxValue = numberAttr(object, def.max)
		if maxValue == nil then
			maxValue = firstNumber(object, def.oldMax) or value
			safeSet(object, def.max, math.max(0, maxValue))
		end

		value = math.clamp(value, 0, math.max(0, maxValue))
		safeSet(object, def.cur, value)

		for _, alias in ipairs(def.oldCur) do
			if alias ~= oldName and alias ~= def.cur then
				safeSet(object, alias, value)
			end
		end
	elseif kind == "max" then
		value = math.max(0, value)
		safeSet(object, def.max, value)

		for _, alias in ipairs(def.oldMax) do
			if alias ~= oldName and alias ~= def.max then
				safeSet(object, alias, value)
			end
		end

		local current = numberAttr(object, def.cur)
		if current ~= nil and current > value then
			safeSet(object, def.cur, value)
		end
	end
end

local function watchResource(object, def)
	object:GetAttributeChangedSignal(def.cur):Connect(function()
		syncFromCanonical(object, def, "cur")
	end)

	object:GetAttributeChangedSignal(def.max):Connect(function()
		syncFromCanonical(object, def, "max")
	end)

	for _, oldName in ipairs(def.oldCur) do
		if oldName ~= def.cur then
			object:GetAttributeChangedSignal(oldName):Connect(function()
				syncFromLegacy(object, def, oldName, "cur")
			end)
		end
	end

	for _, oldName in ipairs(def.oldMax) do
		if oldName ~= def.max then
			object:GetAttributeChangedSignal(oldName):Connect(function()
				syncFromLegacy(object, def, oldName, "max")
			end)
		end
	end
end

function ResourceManager.Register(object)
	if not object or watched[object] then
		return
	end

	local hasAny = false
	for _, def in pairs(RESOURCES) do
		if resourceExists(object, def) then
			hasAny = true
			initializeResource(object, def)
			watchResource(object, def)
		end
	end

	if hasAny then
		watched[object] = true
	end
end

function ResourceManager.Get(object, resourceName)
	local def = RESOURCES[resourceName]
	if not def or not object then
		return 0, 0, 0
	end

	ResourceManager.Register(object)

	return
		numberAttr(object, def.cur) or 0,
		numberAttr(object, def.max) or 0,
		numberAttr(object, def.reg) or 0
end

function ResourceManager.SetCurrent(object, resourceName, value)
	local def = RESOURCES[resourceName]
	if not def or not object then
		return 0
	end

	ResourceManager.Register(object)

	local maxValue = numberAttr(object, def.max) or 0
	value = math.clamp(tonumber(value) or 0, 0, maxValue)
	object:SetAttribute(def.cur, value)
	return value
end

function ResourceManager.Add(object, resourceName, amount)
	local current = ResourceManager.Get(object, resourceName)
	return ResourceManager.SetCurrent(object, resourceName, current + (tonumber(amount) or 0))
end

function ResourceManager.Take(object, resourceName, amount)
	local current = ResourceManager.Get(object, resourceName)
	local wanted = math.max(0, tonumber(amount) or 0)
	local taken = math.min(current, wanted)

	ResourceManager.SetCurrent(object, resourceName, current - taken)
	return taken
end

local function scan(root)
	ResourceManager.Register(root)
	for _, object in ipairs(root:GetDescendants()) do
		ResourceManager.Register(object)
	end
end

function ResourceManager.Start()
	if started then
		return
	end
	started = true

	scan(Workspace)
	scan(ReplicatedStorage)

	Workspace.DescendantAdded:Connect(function(object)
		task.defer(function()
			ResourceManager.Register(object)
		end)
	end)

	ReplicatedStorage.DescendantAdded:Connect(function(object)
		task.defer(function()
			ResourceManager.Register(object)
		end)
	end)

	print("[ResourceManager] Canonical resources enabled: HP/Fuel/Cargo *_cur *_max *_reg")
end

return ResourceManager
