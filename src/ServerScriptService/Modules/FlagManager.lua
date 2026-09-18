local Workspace = game:GetService("Workspace")

local TeamColors = require(script.Parent.TeamColors)

local FlagManager = {}

local REGION_OWNERS_FOLDER_NAME = "Region_owners"
local TEAM_COLOR_PART_NAME = "Team_color"

local DEFAULT_TEAM_OWNER = 0
local DEFAULT_OWNERSHIP_RADIUS = 150
local DEFAULT_CAPTURE_TIME = 10

local function getRegionOwnersFolder()
	return Workspace:FindFirstChild(REGION_OWNERS_FOLDER_NAME)
end

local function getFlagMain(flag)
	return flag:FindFirstChild("Main")
end

local function getFlagColorPart(flag)
	local direct = flag:FindFirstChild(TEAM_COLOR_PART_NAME)
	if direct and direct:IsA("BasePart") then
		return direct
	end

	local recursive = flag:FindFirstChild(TEAM_COLOR_PART_NAME, true)
	if recursive and recursive:IsA("BasePart") then
		return recursive
	end

	return nil
end

local function getMaxHealth(flag)
	return math.max(0, tonumber(flag:GetAttribute("Max_health")) or 0)
end

local function getCurrentHealth(flag)
	return math.max(0, tonumber(flag:GetAttribute("Current_health")) or 0)
end

function FlagManager.IsDestroyed(flag)
	return flag:GetAttribute("Destroyed") == true
		or getCurrentHealth(flag) <= 0
end

function FlagManager.SetDestroyed(flag, destroyed)
	destroyed = destroyed == true
	flag:SetAttribute("Destroyed", destroyed)

	if destroyed then
		flag:SetAttribute("Contested", false)
		flag:SetAttribute("CaptureProgress", 0)
		flag:SetAttribute("CaptureTeam", 0)

		if not FlagManager.IsBaseFlag(flag) then
			flag:SetAttribute("TeamOwner", DEFAULT_TEAM_OWNER)
		end

		FlagManager.PaintFlag(flag)
	end
end

function FlagManager.GetCaptureTime(flag)
	local captureTime = tonumber(flag:GetAttribute("Capture_time"))

	if captureTime == nil then
		captureTime = DEFAULT_CAPTURE_TIME
		flag:SetAttribute("Capture_time", captureTime)
	end

	return math.max(0.1, captureTime)
end

function FlagManager.IsFlag(model)
	if not model:IsA("Model") then
		return false
	end

	if not getFlagMain(model) then
		return false
	end

	if not getFlagColorPart(model) then
		return false
	end

	return true
end

function FlagManager.IsBaseFlag(flag)
	return string.sub(flag.Name, 1, 5) == "BASE_"
end

function FlagManager.GetTeamOwner(flag)
	local teamOwner = flag:GetAttribute("TeamOwner")

	if teamOwner == nil then
		teamOwner = DEFAULT_TEAM_OWNER
		flag:SetAttribute("TeamOwner", teamOwner)
	end

	return teamOwner
end

function FlagManager.SetTeamOwner(flag, teamOwner)
	if FlagManager.IsBaseFlag(flag) then
		local oldOwner = FlagManager.GetTeamOwner(flag)

		if oldOwner ~= DEFAULT_TEAM_OWNER then
			return
		end
	end

	flag:SetAttribute("TeamOwner", teamOwner)
	FlagManager.PaintFlag(flag)
end

function FlagManager.GetOwnershipRadius(flag)
	local radius = flag:GetAttribute("OwnershipRadius")

	if radius == nil then
		radius = DEFAULT_OWNERSHIP_RADIUS
		flag:SetAttribute("OwnershipRadius", radius)
	end

	return radius
end

function FlagManager.PaintFlag(flag)
	local colorPart = getFlagColorPart(flag)

	if not colorPart then
		return
	end

	local teamOwner = FlagManager.GetTeamOwner(flag)
	colorPart.Color = TeamColors.GetColor(teamOwner)
end

function FlagManager.SetupFlag(flag)
	if not FlagManager.IsFlag(flag) then
		warn("[FlagManager] Bad flag structure:", flag:GetFullName())
		return
	end

	FlagManager.GetTeamOwner(flag)
	FlagManager.GetOwnershipRadius(flag)
	FlagManager.GetCaptureTime(flag)

	if flag:GetAttribute("Show_name") == nil then
		flag:SetAttribute("Show_name", flag.Name)
	end

	local maxHealth = getMaxHealth(flag)
	local currentHealth = getCurrentHealth(flag)

	if flag:GetAttribute("Current_health") == nil and maxHealth > 0 then
		flag:SetAttribute("Current_health", maxHealth)
		currentHealth = maxHealth
	end

	if flag:GetAttribute("CaptureProgress") == nil then
		flag:SetAttribute("CaptureProgress", 0)
	end
	if flag:GetAttribute("CaptureTeam") == nil then
		flag:SetAttribute("CaptureTeam", 0)
	end
	if flag:GetAttribute("Contested") == nil then
		flag:SetAttribute("Contested", false)
	end

	FlagManager.SetDestroyed(flag, currentHealth <= 0)
	FlagManager.PaintFlag(flag)

	local main = getFlagMain(flag)

	if main and main:IsA("BasePart") then
		flag.PrimaryPart = main
	end
end

function FlagManager.GetAllFlags()
	local folder = getRegionOwnersFolder()

	if not folder then
		warn("[FlagManager] Workspace.Region_owners not found")
		return {}
	end

	local flags = {}

	for _, child in ipairs(folder:GetChildren()) do
		if FlagManager.IsFlag(child) then
			table.insert(flags, child)
		end
	end

	return flags
end

function FlagManager.SetupAllFlags()
	for _, flag in ipairs(FlagManager.GetAllFlags()) do
		FlagManager.SetupFlag(flag)
	end
end

function FlagManager.StartAutoSetup()
	local folder = getRegionOwnersFolder()

	if not folder then
		warn("[FlagManager] Workspace.Region_owners not found")
		return
	end

	folder.ChildAdded:Connect(function(child)
		task.wait(0.1)

		if FlagManager.IsFlag(child) then
			FlagManager.SetupFlag(child)
		end
	end)
end

return FlagManager
