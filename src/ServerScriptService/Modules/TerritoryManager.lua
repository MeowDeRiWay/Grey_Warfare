local Workspace = game:GetService("Workspace")

local TeamColors = require(script.Parent.TeamColors)
local FlagManager = require(script.Parent.FlagManager)

local TerritoryManager = {}

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"
local TEAM_COLOR_PART_NAME = "Team_color"
local OWNERSHIP_COLOR_ATTRIBUTE = "Ownership_color"

local UPDATE_INTERVAL = 2

local function getBaseObjectsFolder()
	return Workspace:FindFirstChild(BASE_OBJECTS_FOLDER_NAME)
end

local function getRootPart(object)
	if object:IsA("Model") then
		return object.PrimaryPart
			or object:FindFirstChild("Main")
			or object:FindFirstChildWhichIsA("BasePart", true)
	end

	if object:IsA("BasePart") then
		return object
	end

	return nil
end

local function findOwningFlagForPosition(position, flags)
	local selectedFlag
	local selectedDistance = math.huge

	for _, flag in ipairs(flags) do
		local flagRoot = getRootPart(flag)

		if flagRoot then
			local radius = FlagManager.GetOwnershipRadius(flag)
			local distance = (position - flagRoot.Position).Magnitude

			if distance <= radius and distance < selectedDistance then
				selectedFlag = flag
				selectedDistance = distance
			end
		end
	end

	return selectedFlag
end

local function getFlagOwner(flag)
	if not flag or FlagManager.IsDestroyed(flag) then
		return 0
	end

	return tonumber(FlagManager.GetTeamOwner(flag)) or 0
end

local function paintModelTeamColor(object)
	local teamOwner = tonumber(object:GetAttribute("TeamOwner")) or 0

	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == TEAM_COLOR_PART_NAME then
			descendant.Color = TeamColors.GetColor(teamOwner)
		end
	end
end

local function paintOwnershipPart(part, flags)
	if not part:IsA("BasePart") or part:GetAttribute(OWNERSHIP_COLOR_ATTRIBUTE) ~= true then
		return
	end

	local flag = findOwningFlagForPosition(part.Position, flags)
	local owner = getFlagOwner(flag)

	part.Color = TeamColors.GetColor(owner)
end

local function setupObject(object)
	if not object:IsA("Model") then
		return
	end

	if object:GetAttribute("TeamOwner") == nil then
		object:SetAttribute("TeamOwner", 0)
	end

	local main = object:FindFirstChild("Main")
	if main and main:IsA("BasePart") then
		object.PrimaryPart = main
	end

	paintModelTeamColor(object)
end

function TerritoryManager.SetupAllObjects()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[TerritoryManager] Workspace.Base_objects not found")
		return
	end

	for _, object in ipairs(folder:GetChildren()) do
		setupObject(object)
	end
end

function TerritoryManager.ApplyOwnership()
	local flags = FlagManager.GetAllFlags()
	local folder = getBaseObjectsFolder()

	-- Existing model ownership:
	-- Base_objects inherit TeamOwner from the nearest flag whose radius contains them.
	if folder then
		for _, object in ipairs(folder:GetChildren()) do
			if object:IsA("Model") then
				local objectRoot = getRootPart(object)

				if objectRoot then
					local flag = findOwningFlagForPosition(objectRoot.Position, flags)

					if flag then
						object:SetAttribute("TeamOwner", getFlagOwner(flag))
						paintModelTeamColor(object)
					end
				end
			end
		end
	end

	-- Universal map coloring:
	-- any BasePart with Ownership_color = true is colored directly
	-- from the flag territory containing that exact part.
	for _, object in ipairs(Workspace:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute(OWNERSHIP_COLOR_ATTRIBUTE) == true then
			paintOwnershipPart(object, flags)
		end
	end
end

function TerritoryManager.StartLoop()
	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL)
			TerritoryManager.ApplyOwnership()
		end
	end)
end

function TerritoryManager.StartAutoSetup()
	local folder = getBaseObjectsFolder()

	if folder then
		folder.ChildAdded:Connect(function(child)
			task.wait(0.1)
			setupObject(child)
		end)
	else
		warn("[TerritoryManager] Workspace.Base_objects not found")
	end

	Workspace.DescendantAdded:Connect(function(object)
		task.defer(function()
			if object:IsA("BasePart") and object:GetAttribute(OWNERSHIP_COLOR_ATTRIBUTE) == true then
				paintOwnershipPart(object, FlagManager.GetAllFlags())
			end
		end)
	end)
end

return TerritoryManager
