local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local WarehouseManager = {}

-- VERSION: SUPPLY MAGS V3
-- Додано add_supply:
-- 1 магазин за 5 секунд поповнює Reg_mag_current до Reg_mag_max;
-- потім Utra_mag_current до Utra_mag_max.

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"
local ACTIVE_VEHICLES_FOLDER_NAME = "ActiveVehicles"

local CARGO_TRANSFER_RATE = 0.05 -- 5% Max_cargo / sec
local FUEL_TRANSFER_RATE = 0.10 -- 10% Max_fuel / sec

local SUPPLY_MAG_TIME = 5 -- seconds per magazine

local DEFAULT_TOUCH_RADIUS = 8
local DEFAULT_FUEL_WAREHOUSE_RADIUS = 100

local DEBUG = true

local warehouses = {}
local fuelStations = {}
local supplyProgressByPlayer = {}

local function dprint(...)
	if DEBUG then
		print(...)
	end
end

local function getBaseObjectsFolder()
	return Workspace:FindFirstChild(BASE_OBJECTS_FOLDER_NAME)
end

local function getActiveVehiclesFolder()
	return Workspace:FindFirstChild(ACTIVE_VEHICLES_FOLDER_NAME)
end

local function getMain(model)
	local main = model:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getPart(model, partName)
	local part = model:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function getTeamOwner(model)
	return tonumber(model:GetAttribute("TeamOwner")) or 0
end

local function getPlayerTeamOwner(player)
	local attr = player:GetAttribute("TeamOwner")
	if attr ~= nil then
		return tonumber(attr) or 0
	end

	local teamValue = player:GetAttribute("Team")
	if teamValue ~= nil then
		return tonumber(teamValue) or 0
	end

	if player.Team then
		local teamAttr = player.Team:GetAttribute("TeamOwner")
		if teamAttr ~= nil then
			return tonumber(teamAttr) or 0
		end

		local teamNumber = tonumber(player.Team.Name)
		if teamNumber then
			return teamNumber
		end

		local lowerName = string.lower(player.Team.Name)
		if lowerName == "red" or lowerName == "червоні" or lowerName == "червона" then
			return 1
		end
		if lowerName == "blue" or lowerName == "сині" or lowerName == "синя" then
			return 2
		end
		if lowerName == "seal" then
			return 3
		end
	end

	return 0
end

local function sameTeam(a, b)
	local teamA = getTeamOwner(a)
	local teamB = getTeamOwner(b)

	if teamA == 0 or teamB == 0 then
		return false
	end

	return teamA == teamB
end

local function sameTeamPlayerObject(player, object)
	local playerTeam = getPlayerTeamOwner(player)
	local objectTeam = getTeamOwner(object)

	if playerTeam == 0 or objectTeam == 0 then
		return false
	end

	return playerTeam == objectTeam
end

local function getMountedModulesFolder(vehicle)
	local folder = vehicle:FindFirstChild("MountedModules")
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function getCargoModule(vehicle)
	local folder = getMountedModulesFolder(vehicle)
	if not folder then
		return nil
	end

	for _, module in ipairs(folder:GetChildren()) do
		if module:IsA("Model") and module:GetAttribute("Module") == true then
			if module:GetAttribute("ModuleRole") == "Cargo" then
				return module
			end
		end
	end

	return nil
end

local function getCargoTarget(vehicle)
	local cargoModule = getCargoModule(vehicle)
	if cargoModule then
		return cargoModule
	end

	if vehicle:GetAttribute("Max_cargo") ~= nil then
		return vehicle
	end

	return nil
end

local function hasCargoStorage(vehicle)
	return getCargoTarget(vehicle) ~= nil
end

local function isVehicle(model)
	return model:IsA("Model")
		and model:GetAttribute("TeamOwner") ~= nil
		and (
			model:GetAttribute("Max_fuel") ~= nil
			or model:GetAttribute("Max_cargo") ~= nil
			or getCargoModule(model) ~= nil
		)
end

local function isModelNearPart(model, part)
	local main = getMain(model)
	if not main or not part then
		return false
	end

	local radius = tonumber(part:GetAttribute("Transfer_radius"))
		or tonumber(part:GetAttribute("Touch_radius"))
		or DEFAULT_TOUCH_RADIUS

	local distance = (main.Position - part.Position).Magnitude
	if distance <= radius then
		return true
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }

	local ok, touchingParts = pcall(function()
		return Workspace:GetPartsInPart(part, params)
	end)

	return ok and #touchingParts > 0
end

local function isVehicleNearPart(vehicle, part)
	return isModelNearPart(vehicle, part)
end

local function registerObject(object)
	if not object:IsA("Model") then
		return
	end

	local objectType = object:GetAttribute("ObjectType")

	if objectType == "Warehouse" then
		warehouses[object] = true
		dprint("[WarehouseManager] Warehouse registered:", object.Name)
	elseif objectType == "FuelStation" then
		fuelStations[object] = true
		dprint("[WarehouseManager] FuelStation registered:", object.Name)
	end
end

local function unregisterObject(object)
	warehouses[object] = nil
	fuelStations[object] = nil
end

function WarehouseManager.FindWarehouseNear(sourceModel)
	local sourceMain = getMain(sourceModel)
	if not sourceMain then
		return nil
	end

	local radius = tonumber(sourceModel:GetAttribute("Cargo_radius"))
		or tonumber(sourceModel:GetAttribute("Warehouse_radius"))
		or DEFAULT_FUEL_WAREHOUSE_RADIUS

	if radius <= 0 then
		radius = DEFAULT_FUEL_WAREHOUSE_RADIUS
	end

	local bestWarehouse = nil
	local bestDistance = radius

	for warehouse in pairs(warehouses) do
		if warehouse.Parent and sameTeam(sourceModel, warehouse) then
			local warehouseMain = getMain(warehouse)
			if warehouseMain then
				local distance = (warehouseMain.Position - sourceMain.Position).Magnitude
				if distance <= bestDistance then
					bestDistance = distance
					bestWarehouse = warehouse
				end
			end
		end
	end

	return bestWarehouse
end

function WarehouseManager.CanPayCargo(sourceModel, amount)
	amount = tonumber(amount) or 0

	if amount <= 0 then
		return true
	end

	local warehouse = WarehouseManager.FindWarehouseNear(sourceModel)
	if not warehouse then
		return false
	end

	local currentCargo = tonumber(warehouse:GetAttribute("Current_cargo")) or 0
	return currentCargo >= amount
end

function WarehouseManager.PayCargo(sourceModel, amount)
	amount = tonumber(amount) or 0

	if amount <= 0 then
		return true
	end

	local warehouse = WarehouseManager.FindWarehouseNear(sourceModel)
	if not warehouse then
		return false
	end

	local currentCargo = tonumber(warehouse:GetAttribute("Current_cargo")) or 0

	if currentCargo < amount then
		return false
	end

	warehouse:SetAttribute("Current_cargo", currentCargo - amount)
	return true
end

local function loadVehicleFromWarehouse(vehicle, warehouse, dt)
	if not sameTeam(vehicle, warehouse) then
		return
	end

	local cargoTarget = getCargoTarget(vehicle)
	if not cargoTarget then
		return
	end

	local vehicleCurrent = tonumber(cargoTarget:GetAttribute("Current_cargo")) or 0
	local vehicleMax = tonumber(cargoTarget:GetAttribute("Max_cargo")) or 0
	local warehouseCurrent = tonumber(warehouse:GetAttribute("Current_cargo")) or 0

	if vehicleMax <= 0 or vehicleCurrent >= vehicleMax or warehouseCurrent <= 0 then
		return
	end

	local transfer = vehicleMax * CARGO_TRANSFER_RATE * dt
	transfer = math.min(transfer, vehicleMax - vehicleCurrent, warehouseCurrent)

	if transfer <= 0 then
		return
	end

	cargoTarget:SetAttribute("Current_cargo", vehicleCurrent + transfer)
	warehouse:SetAttribute("Current_cargo", warehouseCurrent - transfer)

	dprint("[WarehouseManager] LOAD cargo:", vehicle.Name, "->", cargoTarget.Name, "+", transfer)
end

local function unloadVehicleToWarehouse(vehicle, warehouse, dt)
	local warehouseTeam = getTeamOwner(warehouse)

	if warehouseTeam == 0 then
		return
	end

	local cargoTarget = getCargoTarget(vehicle)
	if not cargoTarget then
		return
	end

	local vehicleCurrent = tonumber(cargoTarget:GetAttribute("Current_cargo")) or 0
	local vehicleMax = tonumber(cargoTarget:GetAttribute("Max_cargo")) or 0

	local warehouseCurrent = tonumber(warehouse:GetAttribute("Current_cargo")) or 0
	local warehouseMax = tonumber(warehouse:GetAttribute("Max_cargo")) or 0

	if vehicleCurrent <= 0 or vehicleMax <= 0 or warehouseMax <= 0 or warehouseCurrent >= warehouseMax then
		return
	end

	local transfer = vehicleMax * CARGO_TRANSFER_RATE * dt
	transfer = math.min(transfer, vehicleCurrent, warehouseMax - warehouseCurrent)

	if transfer <= 0 then
		return
	end

	cargoTarget:SetAttribute("Current_cargo", vehicleCurrent - transfer)
	warehouse:SetAttribute("Current_cargo", warehouseCurrent + transfer)

	dprint("[WarehouseManager] UNLOAD cargo:", vehicle.Name, "<-", cargoTarget.Name, "-", transfer)
end

local function refuelVehicle(vehicle, fuelStation, dt)
	if not sameTeam(vehicle, fuelStation) then
		return
	end

	local warehouse = WarehouseManager.FindWarehouseNear(fuelStation)
	if not warehouse then
		dprint("[WarehouseManager] No warehouse near fuel station:", fuelStation.Name)
		return
	end

	local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
	local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0

	if maxFuel <= 0 or currentFuel >= maxFuel then
		return
	end

	local warehouseCargo = tonumber(warehouse:GetAttribute("Current_cargo")) or 0
	if warehouseCargo <= 0 then
		dprint("[WarehouseManager] Warehouse has no cargo for fuel:", warehouse.Name)
		return
	end

	local fuelToAdd = maxFuel * FUEL_TRANSFER_RATE * dt
	fuelToAdd = math.min(fuelToAdd, maxFuel - currentFuel, warehouseCargo)

	if fuelToAdd <= 0 then
		return
	end

	vehicle:SetAttribute("Current_fuel", currentFuel + fuelToAdd)
	warehouse:SetAttribute("Current_cargo", warehouseCargo - fuelToAdd)

	dprint("[WarehouseManager] REFUEL:", vehicle.Name, "+", fuelToAdd)
end

local function processWarehouses(vehicle, dt)
	if not hasCargoStorage(vehicle) then
		return
	end

	for warehouse in pairs(warehouses) do
		if warehouse.Parent then
			local addCargo = getPart(warehouse, "add_cargo")
			local getCargo = getPart(warehouse, "get_cargo")

			if addCargo and isVehicleNearPart(vehicle, addCargo) then
				loadVehicleFromWarehouse(vehicle, warehouse, dt)
			end

			if getCargo and isVehicleNearPart(vehicle, getCargo) then
				unloadVehicleToWarehouse(vehicle, warehouse, dt)
			end
		end
	end
end

local function processFuelStations(vehicle, dt)
	for fuelStation in pairs(fuelStations) do
		if fuelStation.Parent then
			local addFuel = getPart(fuelStation, "add_fuel")

			if addFuel and isVehicleNearPart(vehicle, addFuel) then
				refuelVehicle(vehicle, fuelStation, dt)
			end
		end
	end
end

local function tryAddOneMagazine(character, currentAttr, maxAttr)
	local current = tonumber(character:GetAttribute(currentAttr)) or 0
	local maxValue = tonumber(character:GetAttribute(maxAttr)) or 0

	if maxValue <= 0 or current >= maxValue then
		return false
	end

	character:SetAttribute(currentAttr, math.min(maxValue, current + 1))
	return true
end

local function supplyPlayer(player, dt)
	local character = player.Character
	if not character then
		supplyProgressByPlayer[player] = 0
		return
	end

	local nearSupply = false

	for warehouse in pairs(warehouses) do
		if warehouse.Parent and sameTeamPlayerObject(player, warehouse) then
			local addSupply = getPart(warehouse, "add_supply")
			if addSupply and isModelNearPart(character, addSupply) then
				nearSupply = true
				break
			end
		end
	end

	if not nearSupply then
		supplyProgressByPlayer[player] = 0
		return
	end

	local progress = (supplyProgressByPlayer[player] or 0) + dt

	while progress >= SUPPLY_MAG_TIME do
		local added = tryAddOneMagazine(character, "Reg_mag_current", "Reg_mag_max")

		if not added then
			added = tryAddOneMagazine(character, "Utra_mag_current", "Utra_mag_max")
		end

		if not added then
			progress = 0
			break
		end

		progress -= SUPPLY_MAG_TIME
		dprint("[WarehouseManager] SUPPLY magazine:", player.Name)
	end

	supplyProgressByPlayer[player] = progress
end

local function processSupply(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		supplyPlayer(player, dt)
	end
end

function WarehouseManager.SetupAll()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[WarehouseManager] Workspace.Base_objects not found")
		return
	end

	for _, object in ipairs(folder:GetChildren()) do
		registerObject(object)
	end
end

function WarehouseManager.StartAutoSetup()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[WarehouseManager] Workspace.Base_objects not found")
		return
	end

	folder.ChildAdded:Connect(function(child)
		task.wait(0.1)
		registerObject(child)
	end)

	folder.ChildRemoved:Connect(function(child)
		unregisterObject(child)
	end)
end

function WarehouseManager.StartLoop()
	RunService.Heartbeat:Connect(function(dt)
		local activeVehiclesFolder = getActiveVehiclesFolder()
		if activeVehiclesFolder then
			for _, vehicle in ipairs(activeVehiclesFolder:GetChildren()) do
				if isVehicle(vehicle) then
					processWarehouses(vehicle, dt)
					processFuelStations(vehicle, dt)
				end
			end
		end

		processSupply(dt)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	supplyProgressByPlayer[player] = nil
end)

return WarehouseManager
