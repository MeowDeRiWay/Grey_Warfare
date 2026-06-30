local Players = game:GetService("Players")

local spawnFolder = workspace:WaitForChild("Spawn")
local lobbyFolder = spawnFolder:WaitForChild("spawn_sky")

local blueChoice = lobbyFolder:WaitForChild("BLUE_TEAM_SPAWN_CHOISE")
local redChoice = lobbyFolder:WaitForChild("RED_TEAM_SPAWN_CHOISE")

local blueSpawn = spawnFolder:WaitForChild("BLUE_TEAM_START"):WaitForChild("BLUE_MAIN_SPAWN")
local redSpawn = spawnFolder:WaitForChild("RED_TEAM_START"):WaitForChild("RED_MAIN_SPAWN")

local TEAM_DATA = {
	Blue = {
		color = Color3.fromRGB(0, 60, 255),
		spawn = blueSpawn,
	},

	Red = {
		color = Color3.fromRGB(255, 40, 40),
		spawn = redSpawn,
	},
}

local function getPlayerFromTouchedPart(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function applyTeamVisual(player: Player, teamName: string)
	local data = TEAM_DATA[teamName]
	if not data then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local helmet = character:FindFirstChild("Helmet", true)
	if helmet and helmet:IsA("BasePart") then
		helmet.Color = data.color
	end
end

local function teleportPlayer(player: Player, teamName: string)
	local data = TEAM_DATA[teamName]
	if not data then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		warn("Character has no HumanoidRootPart")
		return
	end

	root.CFrame = data.spawn.CFrame + Vector3.new(0, 3, 0)
end

local function selectTeam(player: Player, teamName: string)
	player:SetAttribute("TeamSelected", true)
	player:SetAttribute("TeamName", teamName)

	applyTeamVisual(player, teamName)
	teleportPlayer(player, teamName)
end

blueChoice.Touched:Connect(function(hit)
	local player = getPlayerFromTouchedPart(hit)
	if player then
		selectTeam(player, "Blue")
	end
end)

redChoice.Touched:Connect(function(hit)
	local player = getPlayerFromTouchedPart(hit)
	if player then
		selectTeam(player, "Red")
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("TeamSelected", false)
	player:SetAttribute("TeamName", "")

	player.CharacterAdded:Connect(function()
		task.wait(0.2)

		local teamName = player:GetAttribute("TeamName")
		if teamName == "Blue" or teamName == "Red" then
			applyTeamVisual(player, teamName)
			teleportPlayer(player, teamName)
		end
	end)
end)