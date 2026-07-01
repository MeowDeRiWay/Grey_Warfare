local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local WarehouseManager = {}

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"
local ACTIVE_VEHICLES_FOLDER_NAME = "ActiveVehicles"

local CARGO_TRANSFER_RATE = 0.05 -- 5% Max_cargo / sec
local FUEL_TRANSFER_RATE = 0.10 -- 10% Max_fuel / sec

local warehouses = {}
local fuelStations = {}

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
	return nil
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

local function sameTeam(a, b)
	local teamA = getTeamOwner(a)
	local teamB = getTeamOwner(b)

	if teamA == 0 or teamB == 0 then
		return false
	end

	return teamA == teamB
end

local function isVehicle(model)
	return model:IsA("Model")
		and model:GetAttribute("Max_cargo") ~= nil
		and model:GetAttribute("Current_cargo") ~= nil
		and model:GetAttribute("TeamOwner") ~= nil
end

local function isVehicleTouchingPart(vehicle, part)
	if not vehicle or not part then
		return false
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { vehicle }

	local touchingParts = Workspace:GetPartsInPart(part, params)

	return #touchingParts > 0
end

local function registerObject(object)
	if not object:IsA("Model") then
		return
	end

	local objectType = object:GetAttribute("ObjectType")

	if objectType == "Warehouse" then
		warehouses[object] = true
		print("[WarehouseManager] Warehouse registered:", object.Name)
	elseif objectType == "FuelStation" then
		fuelStations[object] = true
		print("[WarehouseManager] FuelStation registered:", object.Name)
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

	local radius = tonumber(sourceModel:GetAttribute("Cargo_radius")) or 0
	if radius <= 0 then
		return nil
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

	local vehicleCurrent = tonumber(vehicle:GetAttribute("Current_cargo")) or 0
	local vehicleMax = tonumber(vehicle:GetAttribute("Max_cargo")) or 0
	local warehouseCurrent = tonumber(warehouse:GetAttribute("Current_cargo")) or 0

	if vehicleMax <= 0 or vehicleCurrent >= vehicleMax or warehouseCurrent <= 0 then
		return
	end

	local transfer = vehicleMax * CARGO_TRANSFER_RATE * dt
	transfer = math.min(transfer, vehicleMax - vehicleCurrent, warehouseCurrent)

	if transfer <= 0 then
		return
	end

	vehicle:SetAttribute("Current_cargo", vehicleCurrent + transfer)
	warehouse:SetAttribute("Current_cargo", warehouseCurrent - transfer)
end

local function unloadVehicleToWarehouse(vehicle, warehouse, dt)
	if not sameTeam(vehicle, warehouse) then
		return
	end

	local vehicleCurrent = tonumber(vehicle:GetAttribute("Current_cargo")) or 0
	local vehicleMax = tonumber(vehicle:GetAttribute("Max_cargo")) or 0

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

	vehicle:SetAttribute("Current_cargo", vehicleCurrent - transfer)
	warehouse:SetAttribute("Current_cargo", warehouseCurrent + transfer)
end

local function refuelVehicle(vehicle, fuelStation, dt)
	if not sameTeam(vehicle, fuelStation) then
		return
	end

	local warehouse = WarehouseManager.FindWarehouseNear(fuelStation)
	if not warehouse then
		return
	end

	local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
	local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0

	if maxFuel <= 0 or currentFuel >= maxFuel then
		return
	end

	local warehouseCargo = tonumber(warehouse:GetAttribute("Current_cargo")) or 0
	if warehouseCargo <= 0 then
		return
	end

	local fuelToAdd = maxFuel * FUEL_TRANSFER_RATE * dt
	fuelToAdd = math.min(fuelToAdd, maxFuel - currentFuel, warehouseCargo)

	if fuelToAdd <= 0 then
		return
	end

	vehicle:SetAttribute("Current_fuel", currentFuel + fuelToAdd)
	warehouse:SetAttribute("Current_cargo", warehouseCargo - fuelToAdd)
end

local function processWarehouses(vehicle, dt)
	for warehouse in pairs(warehouses) do
		if warehouse.Parent then
			local addCargo = getPart(warehouse, "add_cargo")
			local getCargo = getPart(warehouse, "get_cargo")

			if addCargo and isVehicleTouchingPart(vehicle, addCargo) then
				loadVehicleFromWarehouse(vehicle, warehouse, dt)
			end

			if getCargo and isVehicleTouchingPart(vehicle, getCargo) then
				unloadVehicleToWarehouse(vehicle, warehouse, dt)
			end
		end
	end
end

local function processFuelStations(vehicle, dt)
	for fuelStation in pairs(fuelStations) do
		if fuelStation.Parent then
			local addFuel = getPart(fuelStation, "add_fuel")

			if addFuel and isVehicleTouchingPart(vehicle, addFuel) then
				refuelVehicle(vehicle, fuelStation, dt)
			end
		end
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
		if not activeVehiclesFolder then
			return
		end

		for _, vehicle in ipairs(activeVehiclesFolder:GetChildren()) do
			if isVehicle(vehicle) then
				processWarehouses(vehicle, dt)
				processFuelStations(vehicle, dt)
			end
		end
	end)
end

return WarehouseManager