local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local helicopterControlRemote = remotes:WaitForChild("HelicopterControl")

local liftUpHeld = false
local descendHeld = false

local function sendLift()
	local lift = 0

	if liftUpHeld and not descendHeld then
		lift = 1
	elseif descendHeld and not liftUpHeld then
		lift = -1
	end

	helicopterControlRemote:FireServer({
		Lift = lift,
	})
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		liftUpHeld = true
		sendLift()
	elseif input.KeyCode == Enum.KeyCode.Z then
		descendHeld = true
		sendLift()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Q then
		liftUpHeld = false
		sendLift()
	elseif input.KeyCode == Enum.KeyCode.Z then
		descendHeld = false
		sendLift()
	end
end)
