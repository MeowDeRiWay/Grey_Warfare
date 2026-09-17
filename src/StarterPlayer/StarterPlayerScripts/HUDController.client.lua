local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Kill the old universal HUD if some old script already created it.
local oldMainHUD = playerGui:FindFirstChild("MainHUD")
if oldMainHUD then
	oldMainHUD:Destroy()
end

local folder = script.Parent:WaitForChild("HUDs")
local Shared = require(folder:WaitForChild("HUDShared"))
local InfantryHUD = require(folder:WaitForChild("InfantryHUD"))
local GroundHUD = require(folder:WaitForChild("GroundHUD"))
local HelicopterHUD = require(folder:WaitForChild("HelicopterHUD"))
local PlaneHUD = require(folder:WaitForChild("PlaneHUD"))

InfantryHUD.Create(playerGui)
GroundHUD.Create(playerGui)
HelicopterHUD.Create(playerGui)
PlaneHUD.Create(playerGui)

local currentState = nil
local currentVehicle = nil
local accumulator = 0
local UPDATE_RATE = 0.05

local function classify(vehicle)
	if not vehicle then
		return "Infantry"
	end

	if vehicle:GetAttribute("Plane") == true
		or vehicle:GetAttribute("VehicleType") == "Plane"
	then
		return "Plane"
	end

	if vehicle:GetAttribute("VehicleType") == "Helicopter" then
		return "Helicopter"
	end

	return "Ground"
end

local function setState(state)
	if state == currentState then
		return
	end

	currentState = state
	InfantryHUD.SetEnabled(state == "Infantry")
	GroundHUD.SetEnabled(state == "Ground")
	HelicopterHUD.SetEnabled(state == "Helicopter")
	PlaneHUD.SetEnabled(state == "Plane")

	print("[HUDRouter] State:", state)
end

RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < UPDATE_RATE then
		return
	end
	accumulator = 0

	currentVehicle = Shared.getControlledVehicle(player)
	local state = classify(currentVehicle)
	setState(state)

	if state == "Infantry" then
		InfantryHUD.Update()
	elseif state == "Ground" then
		GroundHUD.Update(currentVehicle)
	elseif state == "Helicopter" then
		HelicopterHUD.Update(currentVehicle)
	elseif state == "Plane" then
		PlaneHUD.Update(currentVehicle)
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.25)
	currentState = nil
	setState("Infantry")
end)

setState("Infantry")
print("[HUDRouter] 4-state HUD system loaded")
