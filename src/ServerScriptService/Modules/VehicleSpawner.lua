local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local VehicleDriveController = require(script.Parent.VehicleDriveController)
local TeamColors = require(script.Parent.TeamColors)

local VehicleSpawner = {}

local VEHICLES_FOLDER_NAME = "Vehicles"
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

local function getPlayerTeamOwner(player)
	local attr = player:GetAttribute("TeamOwner")
	if attr ~= nil then
		return attr
	end

	local teamValue = player:GetAttribute("Team")
	if teamValue ~= nil then
		return teamValue
	end

	if player.Team then
		local teamAttr = player.Team:GetAttribute("TeamOwner")
		if teamAttr ~= nil then
			return teamAttr
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
	end

	return nil
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

	if seat and seat:IsA("Seat") then
		return seat
	end

	if seat and seat:IsA("VehicleSeat") then
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

local function protectDriverSeat(vehicle)
	local driverSeat = getDriverSeat(vehicle)

	if not driverSeat then
		warn("[VehicleSpawner] Driver_seat not found or is not Seat/VehicleSeat:", vehicle.Name)
		return
	end

	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = driverSeat.Occupant

		if not humanoid then
			return
		end

		local character = humanoid.Parent
		local player = Players:GetPlayerFromCharacter(character)

		if not player then
			humanoid.Sit = false
			return
		end

		local ownerUserId = vehicle:GetAttribute("OwnerUserId")
		local vehicleTeamOwner = vehicle:GetAttribute("TeamOwner")
		local playerTeamOwner = getPlayerTeamOwner(player)

		if ownerUserId ~= player.UserId then
			print("[VehicleSpawner] Seat access denied:", player.Name, "tried to steal", vehicle.Name)
			humanoid.Sit = false
			return
		end

		if tonumber(vehicleTeamOwner) ~= tonumber(playerTeamOwner) then
			print("[VehicleSpawner] Seat team denied:", player.Name, "vehicle:", vehicleTeamOwner, "player:", playerTeamOwner)
			humanoid.Sit = false
			return
		end

		print("my_summer_car")
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

function VehicleSpawner.SpawnVehicle(player, vehicleName, spawnCFrame, teamOwner)
	local playerTeamOwner = getPlayerTeamOwner(player)

	if playerTeamOwner == nil then
		warn("[VehicleSpawner] Spawn denied: player has no TeamOwner:", player.Name)
		return nil
	end

	if tonumber(playerTeamOwner) ~= tonumber(teamOwner) then
		warn(
			"[VehicleSpawner] Spawn denied: wrong team:",
			player.Name,
			"PlayerTeamOwner:",
			playerTeamOwner,
			"SpawnTeamOwner:",
			teamOwner
		)

		return nil
	end

	local vehiclesFolder = ReplicatedStorage:WaitForChild(VEHICLES_FOLDER_NAME)
	local template = vehiclesFolder:FindFirstChild(vehicleName)

	if not template then
		warn("[VehicleSpawner] Vehicle template not found:", vehicleName)
		return nil
	end

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
		local vehicleSize = vehicle:GetExtentsSize()
		local spawnOffsetY = (vehicleSize.Y / 2) + 0.2

		vehicle:PivotTo(spawnCFrame + Vector3.new(0, spawnOffsetY, 0))
	else
		warn("[VehicleSpawner] Vehicle has no PrimaryPart:", vehicle.Name)
	end

	paintVehicle(vehicle, teamOwner or 0)
	protectDriverSeat(vehicle)
	seatOwner(player, vehicle)
	VehicleDriveController.RegisterVehicle(vehicle, player)

	print("[VehicleSpawner] Spawned vehicle:", vehicle.Name, "Owner:", player.Name, "TeamOwner:", teamOwner)

	return vehicle
end


return VehicleSpawner