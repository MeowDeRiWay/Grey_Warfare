local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local spawnFolder = workspace:WaitForChild("Spawn")

local lobbyFolder = spawnFolder:WaitForChild("spawn_sky")

local blueChoice = lobbyFolder:WaitForChild("BLUE_TEAM_SPAWN_CHOISE")
local redChoice = lobbyFolder:WaitForChild("RED_TEAM_SPAWN_CHOISE")

local blueSpawn = spawnFolder:WaitForChild("BLUE_TEAM_START"):WaitForChild("BLUE_MAIN_SPAWN")
local redSpawn = spawnFolder:WaitForChild("RED_TEAM_START"):WaitForChild("RED_MAIN_SPAWN")

local charactersFolder = ReplicatedStorage:WaitForChild("Characters")
local soldierTemplate = charactersFolder:WaitForChild("Soldier")

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

local function clearOldSoldierSkin(character: Model)
	local oldSkin = character:FindFirstChild("SoldierSkin")
	if oldSkin then
		oldSkin:Destroy()
	end
end

local function hideDefaultCharacter(character: Model)
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("BasePart") then
			if obj.Name ~= "HumanoidRootPart" then
				obj.Transparency = 1
			end
		elseif obj:IsA("Decal") then
			obj.Transparency = 1
		end
	end
end

local function weldPart(part: BasePart, root: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

local function applySoldierSkin(player: Player, teamName: string)
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

	clearOldSoldierSkin(character)
	hideDefaultCharacter(character)

	local skin = soldierTemplate:Clone()
	skin.Name = "SoldierSkin"
	skin.Parent = character

	local body = skin:FindFirstChild("Body", true)
	local helmet = skin:FindFirstChild("Helmet", true)

	if not body or not body:IsA("BasePart") then
		warn("Soldier model has no Body part")
		return
	end

	if not helmet or not helmet:IsA("BasePart") then
		warn("Soldier model has no Helmet part")
		return
	end

	body.Size = Vector3.new(0.5, 1.8, 1)
	helmet.Size = Vector3.new(0.55, 0.35, 1.05)

	body.Color = Color3.fromRGB(90, 90, 90)
	helmet.Color = data.color

	body.CFrame = root.CFrame
	helmet.CFrame = root.CFrame * CFrame.new(0, 1.1, 0)

	weldPart(body, root)
	weldPart(helmet, root)
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
		return
	end

	root.CFrame = data.spawn.CFrame + Vector3.new(0, 3, 0)
end

local function selectTeam(player: Player, teamName: string)
	if player:GetAttribute("TeamSelected") then
		return
	end

	player:SetAttribute("TeamSelected", true)
	player:SetAttribute("TeamName", teamName)

	applySoldierSkin(player, teamName)
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
end)
