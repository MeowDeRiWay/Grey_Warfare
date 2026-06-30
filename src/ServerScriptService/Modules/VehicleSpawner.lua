local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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

local function getTeamColorPart(vehicle)
	local part = vehicle:FindFirstChild("Team_color", true)

	if part and part:IsA("BasePart") then
		return part
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

function VehicleSpawner.SpawnVehicle(vehicleName, spawnCFrame, teamOwner)
	local vehiclesFolder = ReplicatedStorage:WaitForChild(VEHICLES_FOLDER_NAME)
	local template = vehiclesFolder:FindFirstChild(vehicleName)

	if not template then
		warn("[VehicleSpawner] Vehicle template not found:", vehicleName)
		return nil
	end

	local vehicle = template:Clone()
	vehicle.Name = vehicleName .. "_" .. tostring(os.time())

	vehicle:SetAttribute("TeamOwner", teamOwner or 0)

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
		vehicle:PivotTo(spawnCFrame)
	else
		warn("[VehicleSpawner] Vehicle has no PrimaryPart:", vehicle.Name)
	end

	paintVehicle(vehicle, teamOwner or 0)

	print("[VehicleSpawner] Spawned vehicle:", vehicle.Name, "TeamOwner:", teamOwner)

	return vehicle
end

return VehicleSpawner