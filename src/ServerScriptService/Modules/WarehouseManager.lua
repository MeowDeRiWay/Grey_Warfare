local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local WarehouseManager = {}

-- VERSION: REWORK MOBILE PROVIDERS V6
-- Єдина логіка для стаціонарних будівель і мобільних модулів техніки.
-- Підтримка:
--   ObjectType = "Warehouse"        + add_cargo / get_cargo
--   ObjectType = "FuelStation"      + add_fuel
--   ObjectType = "SupplyStation"    + add_supply
--   ModuleRole = "Cargo"            + Current_cargo / Max_cargo
--   ModuleRole = "FuelStation"      + add_fuel
--   ModuleRole = "SupplyStation"    + add_supply
--
-- Джерело cargo для Fuel/Supply:
--   1) Cargo-модуль на тій самій техніці;
--   2) найближчий Warehouse або Cargo-модуль своєї команди в Cargo_radius.

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"
local ACTIVE_VEHICLES_FOLDER_NAME = "ActiveVehicles"

local CARGO_TRANSFER_RATE = 0.05 -- 5% Max_cargo / sec
local FUEL_TRANSFER_RATE = 0.10 -- 10% Max_fuel / sec
local DEFAULT_SUPPLY_TIME = 5 -- seconds per magazine
local DEFAULT_TOUCH_RADIUS = 8
local DEFAULT_CARGO_RADIUS = 100
local DEFAULT_MAG_CARGO_COST = 1
local DEFAULT_FUEL_CARGO_COST = 1 -- 1 cargo -> 1 fuel point

local DEBUG = true

local staticObjects = {}
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
	if not model then
		return nil
	end

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
	if not model then
		return nil
	end

	local part = model:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function getTeamOwner(model)
	return tonumber(model and model:GetAttribute("TeamOwner")) or 0
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

local function getVehicleFromModule(module)
	local current = module.Parent
	while current and current ~= Workspace do
		if current:IsA("Model") and current:GetAttribute("OwnerUserId") ~= nil then
			return current
		end
		current = current.Parent
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

	if vehicle and vehicle:GetAttribute("Max_cargo") ~= nil then
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

local function registerObject(object)
	if not object:IsA("Model") then
		return
	end

	local objectType = object:GetAttribute("ObjectType")
	if objectType == "Warehouse" or objectType == "FuelStation" or objectType == "SupplyStation" then
		staticObjects[object] = true
		dprint("[WarehouseManager V6] Static object registered:", object.Name, objectType)
	end
end

local function unregisterObject(object)
	staticObjects[object] = nil
end

local function getStaticObjectsByRole(role)
	local result = {}

	for object in pairs(staticObjects) do
		if object.Parent and object:GetAttribute("ObjectType") == role then
			table.insert(result, object)
		end
	end

	return result
end

local function getMobileModulesByRole(role)
	local result = {}
	local activeVehiclesFolder = getActiveVehiclesFolder()
	if not activeVehiclesFolder then
		return result
	end

	for _, vehicle in ipairs(activeVehiclesFolder:GetChildren()) do
		if vehicle:IsA("Model") then
			local modulesFolder = getMountedModulesFolder(vehicle)
			if modulesFolder then
				for _, module in ipairs(modulesFolder:GetChildren()) do
					if module:IsA("Model") and module:GetAttribute("Module") == true then
						if module:GetAttribute("ModuleRole") == role then
							table.insert(result, module)
						end
					end
				end
			end
		end
	end

	return result
end

local function getProvidersByRole(role)
	local result = {}

	for _, object in ipairs(getStaticObjectsByRole(role)) do
		table.insert(result, object)
	end

	for _, module in ipairs(getMobileModulesByRole(role)) do
		table.insert(result, module)
	end

	return result
end

local function findCargoSourceNear(sourceModel, teamOwner, radiusOverride)
	local sourceMain = getMain(sourceModel)
	if not sourceMain then
		return nil
	end

	local radius = tonumber(radiusOverride)
		or tonumber(sourceModel:GetAttribute("Cargo_radius"))
		or tonumber(sourceModel:GetAttribute("Warehouse_radius"))
		or DEFAULT_CARGO_RADIUS

	if radius <= 0 then
		radius = DEFAULT_CARGO_RADIUS
	end

	local bestSource = nil
	local bestDistance = radius

	-- Стаціонарні склади.
	for object in pairs(staticObjects) do
		if object.Parent and object:GetAttribute("ObjectType") == "Warehouse" then
			if getTeamOwner(object) == teamOwner then
				local cargoCurrent = tonumber(object:GetAttribute("Current_cargo")) or 0
				if cargoCurrent > 0 then
					local main = getMain(object)
					if main then
						local distance = (main.Position - sourceMain.Position).Magnitude
						if distance <= bestDistance then
							bestDistance = distance
							bestSource = object
						end
					end
				end
			end
		end
	end

	-- Мобільні cargo-модулі.
	for _, cargoModule in ipairs(getMobileModulesByRole("Cargo")) do
		if cargoModule.Parent and getTeamOwner(cargoModule) == teamOwner and cargoModule ~= sourceModel then
			local cargoCurrent = tonumber(cargoModule:GetAttribute("Current_cargo")) or 0
			if cargoCurrent > 0 then
				local main = getMain(cargoModule)
				if main then
					local distance = (main.Position - sourceMain.Position).Magnitude
					if distance <= bestDistance then
						bestDistance = distance
						bestSource = cargoModule
					end
				end
			end
		end
	end

	return bestSource
end

local function getLocalCargoSourceForProvider(provider)
	local vehicle = getVehicleFromModule(provider)
	if not vehicle then
		return nil
	end

	local cargoTarget = getCargoTarget(vehicle)
	if cargoTarget then
		local currentCargo = tonumber(cargoTarget:GetAttribute("Current_cargo")) or 0
		if currentCargo > 0 then
			return cargoTarget
		end
	end

	return nil
end

local function getCargoSourceForProvider(provider)
	-- 1. Спочатку cargo-модуль на тій самій техніці.
	local localSource = getLocalCargoSourceForProvider(provider)
	if localSource then
		return localSource
	end

	-- 2. Потім найближчий склад або cargo-модуль своєї команди.
	local teamOwner = getTeamOwner(provider)
	if teamOwner == 0 then
		return nil
	end

	return findCargoSourceNear(provider, teamOwner, provider:GetAttribute("Cargo_radius"))
end

local function takeCargoFromSource(cargoSource, amount)
	amount = tonumber(amount) or 0
	if not cargoSource or amount <= 0 then
		return 0
	end

	local currentCargo = tonumber(cargoSource:GetAttribute("Current_cargo")) or 0
	local taken = math.min(currentCargo, amount)

	if taken <= 0 then
		return 0
	end

	cargoSource:SetAttribute("Current_cargo", currentCargo - taken)
	return taken
end

function WarehouseManager.FindWarehouseNear(sourceModel)
	return findCargoSourceNear(sourceModel, getTeamOwner(sourceModel), sourceModel:GetAttribute("Cargo_radius"))
end

function WarehouseManager.CanPayCargo(sourceModel, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return true
	end

	local cargoSource = findCargoSourceNear(sourceModel, getTeamOwner(sourceModel), sourceModel:GetAttribute("Cargo_radius"))
	if not cargoSource then
		return false
	end

	local currentCargo = tonumber(cargoSource:GetAttribute("Current_cargo")) or 0
	return currentCargo >= amount
end

function WarehouseManager.PayCargo(sourceModel, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return true
	end

	local cargoSource = findCargoSourceNear(sourceModel, getTeamOwner(sourceModel), sourceModel:GetAttribute("Cargo_radius"))
	if not cargoSource then
		return false
	end

	return takeCargoFromSource(cargoSource, amount) >= amount
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

	dprint("[WarehouseManager V6] LOAD cargo:", vehicle.Name, "->", cargoTarget.Name, "+", transfer)
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

	dprint("[WarehouseManager V6] UNLOAD cargo:", vehicle.Name, "<-", cargoTarget.Name, "-", transfer)
end

local function refuelVehicleFromProvider(vehicle, provider, dt)
	if not sameTeam(vehicle, provider) then
		return
	end

	local addFuel = getPart(provider, "add_fuel")
	if not addFuel or not isModelNearPart(vehicle, addFuel) then
		return
	end

	local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
	local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0
	if maxFuel <= 0 or currentFuel >= maxFuel then
		return
	end

	local cargoSource = getCargoSourceForProvider(provider)
	if not cargoSource then
		dprint("[WarehouseManager V6] No cargo source for fuel provider:", provider.Name)
		return
	end

	local fuelWanted = maxFuel * FUEL_TRANSFER_RATE * dt
	fuelWanted = math.min(fuelWanted, maxFuel - currentFuel)

	local cargoCostPerFuel = tonumber(provider:GetAttribute("Cargo_per_fuel")) or DEFAULT_FUEL_CARGO_COST
	if cargoCostPerFuel <= 0 then
		cargoCostPerFuel = DEFAULT_FUEL_CARGO_COST
	end

	local cargoNeeded = fuelWanted * cargoCostPerFuel
	local cargoTaken = takeCargoFromSource(cargoSource, cargoNeeded)
	local fuelToAdd = cargoTaken / cargoCostPerFuel

	if fuelToAdd <= 0 then
		return
	end

	vehicle:SetAttribute("Current_fuel", currentFuel + fuelToAdd)
	dprint("[WarehouseManager V6] REFUEL:", vehicle.Name, "+", fuelToAdd, "Provider:", provider.Name, "Cargo:", cargoSource.Name)
end

local function processCargoLoading(vehicle, dt)
	if not hasCargoStorage(vehicle) then
		return
	end

	for object in pairs(staticObjects) do
		if object.Parent and object:GetAttribute("ObjectType") == "Warehouse" then
			local addCargo = getPart(object, "add_cargo")
			local getCargo = getPart(object, "get_cargo")

			if addCargo and isModelNearPart(vehicle, addCargo) then
				loadVehicleFromWarehouse(vehicle, object, dt)
			end

			if getCargo and isModelNearPart(vehicle, getCargo) then
				unloadVehicleToWarehouse(vehicle, object, dt)
			end
		end
	end
end

local function processFuelProviders(vehicle, dt)
	for _, provider in ipairs(getProvidersByRole("FuelStation")) do
		if provider.Parent then
			refuelVehicleFromProvider(vehicle, provider, dt)
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

local function findSupplyProviderNearPlayer(player, character)
	for _, provider in ipairs(getProvidersByRole("SupplyStation")) do
		if provider.Parent and sameTeamPlayerObject(player, provider) then
			local addSupply = getPart(provider, "add_supply")
			if addSupply and isModelNearPart(character, addSupply) then
				return provider
			end
		end
	end

	return nil
end

local function supplyPlayer(player, dt)
	local character = player.Character
	if not character then
		supplyProgressByPlayer[player] = 0
		return
	end

	local provider = findSupplyProviderNearPlayer(player, character)
	if not provider then
		supplyProgressByPlayer[player] = 0
		return
	end

	local supplyTime = tonumber(provider:GetAttribute("Supply_time")) or DEFAULT_SUPPLY_TIME
	if supplyTime <= 0 then
		supplyTime = DEFAULT_SUPPLY_TIME
	end

	local progress = (supplyProgressByPlayer[player] or 0) + dt

	while progress >= supplyTime do
		local cargoSource = getCargoSourceForProvider(provider)
		if not cargoSource then
			dprint("[WarehouseManager V6] No cargo source for supply provider:", provider.Name)
			progress = supplyTime
			break
		end

		local magCargoCost = tonumber(provider:GetAttribute("Cargo_per_mag")) or DEFAULT_MAG_CARGO_COST
		if magCargoCost <= 0 then
			magCargoCost = DEFAULT_MAG_CARGO_COST
		end

		local cargoTaken = takeCargoFromSource(cargoSource, magCargoCost)
		if cargoTaken < magCargoCost then
			progress = supplyTime
			break
		end

		local added = tryAddOneMagazine(character, "Reg_mag_current", "Reg_mag_max")
		if not added then
			added = tryAddOneMagazine(character, "Utra_mag_current", "Utra_mag_max")
		end

		if not added then
			-- Гравець повний. Повертаємо cargo назад.
			local currentCargo = tonumber(cargoSource:GetAttribute("Current_cargo")) or 0
			cargoSource:SetAttribute("Current_cargo", currentCargo + cargoTaken)
			progress = 0
			break
		end

		progress -= supplyTime
		dprint("[WarehouseManager V6] SUPPLY magazine:", player.Name, "Provider:", provider.Name, "Cargo:", cargoSource.Name)
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
		warn("[WarehouseManager V6] Workspace.Base_objects not found")
		return
	end

	for _, object in ipairs(folder:GetChildren()) do
		registerObject(object)
	end
end

function WarehouseManager.StartAutoSetup()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[WarehouseManager V6] Workspace.Base_objects not found")
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
					processCargoLoading(vehicle, dt)
					processFuelProviders(vehicle, dt)
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
