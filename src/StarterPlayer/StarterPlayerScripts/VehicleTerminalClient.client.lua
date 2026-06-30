local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local vehicleSpawnRemote = remotes:WaitForChild("VehicleSpawnRequest")

local currentTerminal = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VehicleTerminalGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(300, 180)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundTransparency = 0.1
frame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Text = "Vehicle Terminal"
title.TextScaled = true
title.Parent = frame

local cargoButton = Instance.new("TextButton")
cargoButton.Size = UDim2.new(1, -30, 0, 50)
cargoButton.Position = UDim2.fromOffset(15, 60)
cargoButton.Text = "Spawn Cargo"
cargoButton.TextScaled = true
cargoButton.Parent = frame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(1, -30, 0, 40)
closeButton.Position = UDim2.fromOffset(15, 125)
closeButton.Text = "Close"
closeButton.TextScaled = true
closeButton.Parent = frame

vehicleSpawnRemote.OnClientEvent:Connect(function(action, terminal)
	if action ~= "OpenMenu" then
		return
	end

	currentTerminal = terminal
	screenGui.Enabled = true
end)

cargoButton.MouseButton1Click:Connect(function()
	if not currentTerminal then
		return
	end

	vehicleSpawnRemote:FireServer(currentTerminal, "Cargo")
	screenGui.Enabled = false
end)

closeButton.MouseButton1Click:Connect(function()
	screenGui.Enabled = false
	currentTerminal = nil
end)