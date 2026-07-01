local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "VehicleHud"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 260, 0, 110)
frame.Position = UDim2.new(0, 20, 1, -130)
frame.BackgroundTransparency = 0.25
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 25)
title.Position = UDim2.new(0, 10, 0, 8)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextScaled = true
title.Text = "Vehicle"
title.Parent = frame

local fuel = Instance.new("TextLabel")
fuel.Size = UDim2.new(1, -20, 0, 25)
fuel.Position = UDim2.new(0, 10, 0, 42)
fuel.BackgroundTransparency = 1
fuel.TextXAlignment = Enum.TextXAlignment.Left
fuel.TextScaled = true
fuel.Text = "Паливо: 0 / 0"
fuel.Parent = frame

local health = Instance.new("TextLabel")
health.Size = UDim2.new(1, -20, 0, 25)
health.Position = UDim2.new(0, 10, 0, 72)
health.BackgroundTransparency = 1
health.TextXAlignment = Enum.TextXAlignment.Left
health.TextScaled = true
health.Text = "Міцність: 0 / 0"
health.Parent = frame

local function getCurrentVehicle()
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local seat = humanoid.SeatPart
	if not seat or seat.Name ~= "Driver_seat" then
		return nil
	end

	local model = seat:FindFirstAncestorOfClass("Model")
	return model
end

RunService.RenderStepped:Connect(function()
	local vehicle = getCurrentVehicle()

	if not vehicle then
		gui.Enabled = false
		return
	end

	gui.Enabled = true

	local currentFuel = vehicle:GetAttribute("Current_fuel") or 0
	local maxFuel = vehicle:GetAttribute("Max_fuel") or 0

	local currentHealth = vehicle:GetAttribute("Current_health") or 0
	local maxHealth = vehicle:GetAttribute("Max_health") or 0

	title.Text = vehicle:GetAttribute("VehicleRole") or vehicle.Name
	fuel.Text = string.format("Паливо: %.0f / %.0f", currentFuel, maxFuel)
	health.Text = string.format("Міцність: %.0f / %.0f", currentHealth, maxHealth)
end)