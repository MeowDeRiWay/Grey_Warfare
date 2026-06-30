local Workspace = game:GetService("Workspace")

local TeamColors = require(script.Parent.TeamColors)

local FlagManager = {}

local REGION_OWNERS_FOLDER_NAME = "Region_owners"

local DEFAULT_TEAM_OWNER = 0
local DEFAULT_OWNERSHIP_RADIUS = 100

local function getRegionOwnersFolder()
	return Workspace:FindFirstChild(REGION_OWNERS_FOLDER_NAME)
end

local function getFlagMain(flag)
	return flag:FindFirstChild("Main")
end

local function getFlagColorPart(flag)
	return flag:FindFirstChild("team_owner")
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

	if not colorPart or not colorPart:IsA("BasePart") then
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
	local flags = FlagManager.GetAllFlags()

	for _, flag in ipairs(flags) do
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