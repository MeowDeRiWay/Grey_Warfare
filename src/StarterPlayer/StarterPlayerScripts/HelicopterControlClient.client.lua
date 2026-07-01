local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local helicopterControlRemote = remotes:WaitForChild("HelicopterControl")

local zDown = false
local xDown = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Z then
		zDown = true
	elseif input.KeyCode == Enum.KeyCode.X then
		xDown = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Z then
		zDown = false
	elseif input.KeyCode == Enum.KeyCode.X then
		xDown = false
	end
end)

RunService.RenderStepped:Connect(function()
	local lift = 0

	if zDown then
		lift += 1
	end

	if xDown then
		lift -= 1
	end

	helicopterControlRemote:FireServer({
		Lift = lift,
	})
end)