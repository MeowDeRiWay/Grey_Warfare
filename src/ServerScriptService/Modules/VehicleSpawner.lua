local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local VehicleDriveController = require(script.Parent.VehicleDriveController)
local HelicopterDriveController = require(script.Parent.HelicopterDriveController)
local VehicleModuleManager = require(script.Parent.VehicleModuleManager)
local TeamColors = require(script.Parent.TeamColors)
local VehicleAccess = require(script.Parent.VehicleAccess)

local VehicleSpawner = {}

local ACTIVE_VEHICLES_FOLDER_NAME = "ActiveVehicles"

local function getActiveVehiclesFolder()
	local folder = Workspace:FindFirstChild(ACTIVE_VEHICLES_FOLDER_NAME)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ACTIVE_VEHICLES_FOLDER_NAME
		folder.Parent = Workspace
	end

	return folder
end

local function getTeamColorPart(vehicle)
	local part = vehicle:FindFirstChild("Team_color", true)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function getDriverSeat(vehicle)
	local seat = vehicle:FindFirstChild("Driver_seat", true)
	if seat and (seat:IsA("VehicleSeat") or seat:IsA("Seat")) then
		return seat
	end
	return nil
end

local function getMain(vehicle)
	local main = vehicle:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return nil
end

local function getLandingPart(vehicle)
	local landing = vehicle:FindFirstChild("Ground_level", true)
	if landing and landing:IsA("BasePart") then
		return landing
	end
	return getMain(vehicle)
end

local function paintVehicle(vehicle, teamOwner)
	local colorPart = getTeamColorPart(vehicle)
	if colorPart then
		colorPart.Color = TeamColors.GetColor(teamOwner)
	end
end

local function prepareVehicle(vehicle)
	local main = getMain(vehicle)

	if main then
		vehicle.PrimaryPart = main
	end

	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero

			if vehicle:GetAttribute("VehicleType") == "Helicopter" then
				-- Гелік рухається аркадно через PivotTo, тому фізика вимкнена.
				item.Anchored = true
			else
				item.Anchored = false
			end
		end
	end
end

local function unregisterAnyVehicle(vehicle)
	if vehicle:GetAttribute("VehicleType") == "Helicopter" then
		HelicopterDriveController.UnregisterVehicle(vehicle)
	else
		VehicleDriveController.UnregisterVehicle(vehicle)
	end
end

local function removeOldVehicleForPlayer(player)
	local folder = getActiveVehiclesFolder()

	for _, vehicle in ipairs(folder:GetChildren()) do
		if vehicle:GetAttribute("OwnerUserId") == player.UserId then
			unregisterAnyVehicle(vehicle)
			vehicle:Destroy()
			print("[VehicleSpawner] Old vehicle removed for:", player.Name)
		end
	end
end

local function protectDriverSeat(vehicle)
	local driverSeat = getDriverSeat(vehicle)

	if not driverSeat then
		warn("[VehicleSpawner] Driver_seat not found:", vehicle.Name)
		return
	end

	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = driverSeat.Occupant
		if not humanoid then
			return
		end

		local player = Players:GetPlayerFromCharacter(humanoid.Parent)
		if not player then
			humanoid.Sit = false
			return
		end

		local ownerUserId = vehicle:GetAttribute("OwnerUserId")
		local vehicleTeamOwner = vehicle:GetAttribute("TeamOwner")
		local playerTeamOwner = VehicleAccess.GetPlayerTeamOwner(player)

		if ownerUserId ~= player.UserId then
			humanoid.Sit = false
			return
		end

		if tonumber(vehicleTeamOwner) ~= tonumber(playerTeamOwner) then
			humanoid.Sit = false
			return
		end

		print("[VehicleSpawner] Driver accepted:", player.Name, vehicle.Name)
	end)
end

local function seatOwner(player, vehicle)
	local driverSeat = getDriverSeat(vehicle)
	if not driverSeat then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	task.wait(0.15)
	driverSeat:Sit(humanoid)
end

local function getTemplate(folderName, vehicleName)
	local folder = ReplicatedStorage:FindFirstChild(folderName)

	if not folder then
		warn("[VehicleSpawner] Folder not found:", folderName)
		return nil
	end

	local template = folder:FindFirstChild(vehicleName)

	if not template then
		warn("[VehicleSpawner] Vehicle template not found:", folderName, vehicleName)
		return nil
	end

	return template
end

local function registerController(vehicle, player)
	if vehicle:GetAttribute("VehicleType") == "Helicopter" then
		HelicopterDriveController.RegisterVehicle(vehicle, player)
	else
		VehicleDriveController.RegisterVehicle(vehicle, player)
	end
end

local function getNormalVehicleSpawnCFrame(vehicle, spawnCFrame)
	local vehicleSize = vehicle:GetExtentsSize()
	local offsetY = (vehicleSize.Y / 2) + 0.2
	return spawnCFrame + Vector3.new(0, offsetY, 0)
end

local function getHelicopterSpawnCFrame(vehicle, spawnCFrame)
	local main = getMain(vehicle)
	if not main then
		return spawnCFrame + Vector3.new(0, 1, 0)
	end

	local landingPart = getLandingPart(vehicle) or main
	local clearance = tonumber(vehicle:GetAttribute("Spawn_clearance")) or 1
	local yaw = tonumber(vehicle:GetAttribute("Spawn_yaw")) or 90

	-- Для геліка HSpawn означає рівень посадки.
	-- Ставимо НИЗ Ground_level на HSpawn + 1 студ.
	-- Це прибирає провал під землю, навіть якщо Main не внизу моделі.
	local currentLandingBottomY = landingPart.Position.Y - (landingPart.Size.Y / 2)
	local currentMainY = main.Position.Y
	local desiredLandingBottomY = spawnCFrame.Position.Y + clearance
	local desiredMainY = currentMainY + (desiredLandingBottomY - currentLandingBottomY)

	local spawnPosition = Vector3.new(spawnCFrame.Position.X, desiredMainY, spawnCFrame.Position.Z)
	return CFrame.new(spawnPosition) * CFrame.Angles(0, math.rad(yaw), 0)
end

local function getSpawnCFrame(vehicle, spawnCFrame)
	if vehicle:GetAttribute("VehicleType") == "Helicopter" then
		return getHelicopterSpawnCFrame(vehicle, spawnCFrame)
	end

	return getNormalVehicleSpawnCFrame(vehicle, spawnCFrame)
end

function VehicleSpawner.SpawnVehicle(player, folderName, vehicleName, spawnCFrame, teamOwner)
	local playerTeamOwner = VehicleAccess.GetPlayerTeamOwner(player)

	if playerTeamOwner == nil then
		warn("[VehicleSpawner] Spawn denied: player has no TeamOwner:", player.Name)
		return nil
	end

	if tonumber(playerTeamOwner) ~= tonumber(teamOwner) then
		warn("[VehicleSpawner] Spawn denied: wrong team:", player.Name)
		return nil
	end

	local template = getTemplate(folderName, vehicleName)
	if not template then
		return nil
	end

	removeOldVehicleForPlayer(player)

	local vehicle = template:Clone()
	vehicle.Name = vehicleName .. "_" .. tostring(os.time())

	vehicle:SetAttribute("TeamOwner", teamOwner or 0)
	vehicle:SetAttribute("OwnerUserId", player.UserId)
	vehicle:SetAttribute("OwnerName", player.Name)

	local maxHealth = vehicle:GetAttribute("Max_health")
	if maxHealth and vehicle:GetAttribute("Current_health") == 0 then
		vehicle:SetAttribute("Current_health", maxHealth)
	end

	local maxFuel = vehicle:GetAttribute("Max_fuel")
	if maxFuel and vehicle:GetAttribute("Current_fuel") == 0 then
		vehicle:SetAttribute("Current_fuel", maxFuel)
	end

	prepareVehicle(vehicle)
	vehicle.Parent = getActiveVehiclesFolder()

	if vehicle.PrimaryPart then
		vehicle:PivotTo(getSpawnCFrame(vehicle, spawnCFrame))
	else
		warn("[VehicleSpawner] Vehicle has no PrimaryPart:", vehicle.Name)
	end

	paintVehicle(vehicle, teamOwner or 0)
	VehicleModuleManager.AttachDefaultModules(vehicle, teamOwner or 0)
	protectDriverSeat(vehicle)

	if vehicle:GetAttribute("VehicleType") == "Helicopter" then
		registerController(vehicle, player)
		seatOwner(player, vehicle)
	else
		seatOwner(player, vehicle)
		registerController(vehicle, player)
	end

	print("[VehicleSpawner] Spawned vehicle:", vehicle.Name, "Folder:", folderName)

	return vehicle
end


return VehicleSpawner
