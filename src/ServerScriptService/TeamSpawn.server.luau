local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Modules = ServerScriptService:WaitForChild("Modules")
local SpawnManager = require(Modules:WaitForChild("SpawnManager"))

local TEAM_COLORS = {
	[1] = Color3.fromRGB(255, 40, 40),
	[2] = Color3.fromRGB(0, 60, 255),
}

local touchCooldown = {}

local function getPlayerFromTouchedPart(hit)
	if not hit or not hit:IsA("BasePart") then
		return nil
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function applyTeamVisual(player)
	local teamOwner = tonumber(player:GetAttribute("TeamOwner")) or 0
	local color = TEAM_COLORS[teamOwner]

	if not color then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local helmet = character:FindFirstChild("Helmet", true)
	if helmet and helmet:IsA("BasePart") then
		helmet.Color = color
	end
end

local function selectTeam(player, teamOwner)
	teamOwner = tonumber(teamOwner)

	if not teamOwner or teamOwner <= 0 then
		return
	end

	if touchCooldown[player] then
		return
	end
	touchCooldown[player] = true

	player:SetAttribute("TeamSelected", true)
	player:SetAttribute("TeamOwner", teamOwner)
	player:SetAttribute("TeamName", tostring(teamOwner))

	applyTeamVisual(player)

	task.wait()

	if not SpawnManager.SpawnAtMain(player) then
		warn("[TeamSpawn] Team selected, but Main spawn was not found. Team:", teamOwner)
	end

	print("[TeamSpawn]", player.Name, "selected Team", teamOwner)

	task.delay(1, function()
		touchCooldown[player] = nil
	end)
end

local function setupTeamSelector(object)
	if not object:IsA("BasePart") then
		return
	end

	local newTeam = tonumber(object:GetAttribute("New_team"))
	if not newTeam or newTeam <= 0 then
		return
	end

	if object:GetAttribute("_TeamSelectorConnected") == true then
		return
	end

	object:SetAttribute("_TeamSelectorConnected", true)

	object.Touched:Connect(function(hit)
		local player = getPlayerFromTouchedPart(hit)
		if player then
			selectTeam(player, newTeam)
		end
	end)
end

local function setupAllSelectors()
	for _, object in ipairs(Workspace:GetDescendants()) do
		setupTeamSelector(object)
	end
end

SpawnManager.Start()
setupAllSelectors()

Workspace.DescendantAdded:Connect(function(object)
	task.defer(function()
		setupTeamSelector(object)
	end)
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("TeamSelected", false)
	player:SetAttribute("TeamOwner", 0)
	player:SetAttribute("TeamName", "")

	player.CharacterAdded:Connect(function()
		task.wait(0.2)

		local teamOwner = tonumber(player:GetAttribute("TeamOwner")) or 0

		if teamOwner > 0 then
			applyTeamVisual(player)
			SpawnManager.SpawnAtMain(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	touchCooldown[player] = nil
end)

-- Studio can already contain players when the script is restarted.
for _, player in ipairs(Players:GetPlayers()) do
	if player:GetAttribute("TeamSelected") == nil then
		player:SetAttribute("TeamSelected", false)
	end
	if player:GetAttribute("TeamOwner") == nil then
		player:SetAttribute("TeamOwner", 0)
	end
	if player:GetAttribute("TeamName") == nil then
		player:SetAttribute("TeamName", "")
	end
end

print("[TeamSpawn] Started: selectors use New_team attribute")
