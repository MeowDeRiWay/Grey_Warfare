local Players = game:GetService("Players")

local VehicleConfigManager = {}

local playerConfigs = {}

local function getUserId(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player.UserId
	end
	return tonumber(player)
end

local function getRoot(player)
	local userId = getUserId(player)
	if not userId then
		return nil
	end

	playerConfigs[userId] = playerConfigs[userId] or {}
	return playerConfigs[userId]
end

local function copyConfig(config)
	local result = {}
	for socketPath, moduleName in pairs(config or {}) do
		result[tostring(socketPath)] = tostring(moduleName)
	end
	return result
end

function VehicleConfigManager.GetVehicleConfig(player, vehicleName)
	local root = getRoot(player)
	if not root then
		return {}
	end

	return copyConfig(root[tostring(vehicleName)] or {})
end

function VehicleConfigManager.SetModule(player, vehicleName, socketPath, moduleName)
	if typeof(vehicleName) ~= "string" or vehicleName == "" then
		return false
	end

	if typeof(socketPath) ~= "string" or socketPath == "" then
		return false
	end

	if typeof(moduleName) ~= "string" or moduleName == "" then
		return false
	end

	local root = getRoot(player)
	if not root then
		return false
	end

	root[vehicleName] = root[vehicleName] or {}
	root[vehicleName][socketPath] = moduleName

	print("[VehicleConfigManager] Set module:", player.Name, vehicleName, socketPath, moduleName)
	return true
end

function VehicleConfigManager.ClearSocket(player, vehicleName, socketPath)
	local root = getRoot(player)
	if not root or not root[vehicleName] then
		return false
	end

	root[vehicleName][socketPath] = nil
	return true
end

function VehicleConfigManager.GetAllConfigs(player)
	local root = getRoot(player)
	if not root then
		return {}
	end

	local result = {}
	for vehicleName, config in pairs(root) do
		result[vehicleName] = copyConfig(config)
	end
	return result
end

Players.PlayerRemoving:Connect(function(player)
	-- Поки що зберігання тільки в межах поточного сервера.
	-- DataStore додамо тоді, коли конфіги стануть стабільними.
	playerConfigs[player.UserId] = nil
end)

return VehicleConfigManager
