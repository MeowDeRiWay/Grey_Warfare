local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local spawnFolder = workspace:WaitForChild("Spawn")
local lobbyFolder = spawnFolder:WaitForChild("spawn_sky")

local blueChoice = lobbyFolder:WaitForChild("BLUE_TEAM_SPAWN_CHOISE")
local redChoice = lobbyFolder:WaitForChild("RED_TEAM_SPAWN_CHOISE")

local blueSpawn = spawnFolder:WaitForChild("BLUE_TEAM_START"):WaitForChild("BLUE_MAIN_SPAWN")
local redSpawn = spawnFolder:WaitForChild("RED_TEAM_START"):WaitForChild("RED_MAIN_SPAWN")

local soldierTemplate = ReplicatedStorage:WaitForChild("Characters"):WaitForChild("Soldier")

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

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function prepareSoldierModel(soldier: Model, teamName: string)
	local data = TEAM_DATA[teamName]
	if not data then
		return false
	end

	local humanoid = soldier:FindFirstChildOfClass("Humanoid")
	local root = soldier:FindFirstChild("HumanoidRootPart")
	local body = soldier:FindFirstChild("Body")
	local helmet = soldier:FindFirstChild("Helmet")

	if not humanoid then
		warn("Soldier has no Humanoid")
		return false
	end

	if not root or not root:IsA("BasePart") then
		warn("Soldier has no HumanoidRootPart")
		return false
	end

	if not body or not body:IsA("BasePart") then
		warn("Soldier has no Body")
		return false
	end

	if not helmet or not helmet:IsA("BasePart") then
		warn("Soldier has no Helmet")
		return false
	end

	soldier.PrimaryPart = root

	root.Name = "HumanoidRootPart"
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = false

	body.Anchored = false
	body.CanCollide = false
	body.Massless = true
	body.Color = Color3.fromRGB(90, 90, 90)

	helmet.Anchored = false
	helmet.CanCollide = false
	helmet.Massless = true
	helmet.Color = data.color

	for _, part in ipairs(soldier:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	return true
end

local function spawnSoldierForPlayer(player: Player, teamName: string)
	local data = TEAM_DATA[teamName]
	if not data then
		return
	end

	local oldCharacter = player.Character

	local soldier = soldierTemplate:Clone()
	soldier.Name = player.Name

	if not prepareSoldierModel(soldier, teamName) then
		soldier:Destroy()
		return
	end

	soldier.Parent = workspace
	player.Character = soldier

	soldier:PivotTo(data.spawn.CFrame + Vector3.new(0, 3, 0))

	if oldCharacter and oldCharacter ~= soldier then
		oldCharacter:Destroy()
	end
end

local function selectTeam(player: Player, teamName: string)
	player:SetAttribute("TeamSelected", true)
	player:SetAttribute("TeamName", teamName)

	spawnSoldierForPlayer(player, teamName)
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
			spawnSoldierForPlayer(player, teamName)
		end
	end)
end)