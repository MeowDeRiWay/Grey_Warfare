local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local vehicleSpawnRemote = remotes:WaitForChild("VehicleSpawnRequest")

local currentTerminal = nil
local currentVehicle = "Cargo"

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VehicleTerminalGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(300,180)
frame.Position = UDim2.fromScale(0.5,0.5)
frame.AnchorPoint = Vector2.new(0.5,0.5)
frame.BackgroundTransparency = 0.1
frame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,0,0,40)
title.BackgroundTransparency = 1
title.TextScaled = true
title.Parent = frame

local spawnButton = Instance.new("TextButton")
spawnButton.Size = UDim2.new(1,-30,0,50)
spawnButton.Position = UDim2.fromOffset(15,60)
spawnButton.TextScaled = true
spawnButton.Parent = frame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(1,-30,0,40)
closeButton.Position = UDim2.fromOffset(15,125)
closeButton.Text = "Close"
closeButton.TextScaled = true
closeButton.Parent = frame

vehicleSpawnRemote.OnClientEvent:Connect(function(action, terminal)

	if action ~= "OpenMenu" then
		return
	end

	currentTerminal = terminal

	local objectType = terminal:GetAttribute("ObjectType")

	if objectType == "HeliTerminal" then

		title.Text = "Helicopter Terminal"
		spawnButton.Text = "Spawn Cargo Helicopter"
		currentVehicle = "Cargo_Heli"

	else

		title.Text = "Vehicle Terminal"
		spawnButton.Text = "Spawn Cargo"
		currentVehicle = "Cargo"

	end

	screenGui.Enabled = true

end)

spawnButton.MouseButton1Click:Connect(function()

	if not currentTerminal then
		return
	end

	vehicleSpawnRemote:FireServer(
		currentTerminal,
		currentVehicle
	)

	screenGui.Enabled = false

end)

closeButton.MouseButton1Click:Connect(function()

	screenGui.Enabled = false
	currentTerminal = nil

end)