local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local VehicleDriveController = require(script.Parent.VehicleDriveController)
local HelicopterDriveController = require(script.Parent.HelicopterDriveController)
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

local function paintVehicle(vehicle, teamOwner)
	local colorPart = getTeamColorPart(vehicle)
	if colorPart then
		colorPart.Color = TeamColors.GetColor(teamOwner)
	end
end

local function prepareVehicle(vehicle)
	local main = vehicle:FindFirstChild("Main", true)

	if main and main:IsA("BasePart") then
		vehicle.PrimaryPart = main
	end

	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = false
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
		if not humanoid then return end

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
	if not driverSeat then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

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

local function getSpawnOffsetY(vehicle)
	local vehicleSize = vehicle:GetExtentsSize()
	local offset = (vehicleSize.Y / 2) + 0.2

	if vehicle:GetAttribute("VehicleType") == "Helicopter" then
		offset += tonumber(vehicle:GetAttribute("Spawn_height_bonus")) or 12
	end

	return offset
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
	if not template then return nil end

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
		vehicle:PivotTo(spawnCFrame + Vector3.new(0, getSpawnOffsetY(vehicle), 0))
	else
		warn("[VehicleSpawner] Vehicle has no PrimaryPart:", vehicle.Name)
	end

	paintVehicle(vehicle, teamOwner or 0)
	protectDriverSeat(vehicle)
	seatOwner(player, vehicle)
	registerController(vehicle, player)

	print("[VehicleSpawner] Spawned vehicle:", vehicle.Name, "Folder:", folderName)

	return vehicle
end

return VehicleSpawner