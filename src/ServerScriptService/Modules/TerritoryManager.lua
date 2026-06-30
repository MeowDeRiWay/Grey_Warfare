local Workspace = game:GetService("Workspace")

local TeamColors = require(script.Parent.TeamColors)
local FlagManager = require(script.Parent.FlagManager)

local TerritoryManager = {}

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"

local UPDATE_INTERVAL = 2

local function getBaseObjectsFolder()
	return Workspace:FindFirstChild(BASE_OBJECTS_FOLDER_NAME)
end

local function getRootPart(model)
	if model:IsA("Model") then
		return model.PrimaryPart
			or model:FindFirstChild("Main")
			or model:FindFirstChildWhichIsA("BasePart")
	end

	if model:IsA("BasePart") then
		return model
	end

	return nil
end

local function getColorTarget(object)
	local screen = object:FindFirstChild("Screen", true)
	if screen and screen:IsA("BasePart") then
		return screen
	end

	local teamOwner = object:FindFirstChild("team_owner", true)
	if teamOwner and teamOwner:IsA("BasePart") then
		return teamOwner
	end

	return nil
end

local function paintObject(object)
	local teamOwner = object:GetAttribute("TeamOwner") or 0
	local colorTarget = getColorTarget(object)

	if colorTarget then
		colorTarget.Color = TeamColors.GetColor(teamOwner)
	end
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

	paintObject(object)
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
	local folder = getBaseObjectsFolder()

	if not folder then
		return
	end

	local flags = FlagManager.GetAllFlags()

	for _, object in ipairs(folder:GetChildren()) do
		if object:IsA("Model") then
			local objectRoot = getRootPart(object)

			if objectRoot then
				for _, flag in ipairs(flags) do
					local flagRoot = getRootPart(flag)

					if flagRoot then
						local flagOwner = FlagManager.GetTeamOwner(flag)
						local radius = FlagManager.GetOwnershipRadius(flag)

						if flagOwner ~= 0 then
							local distance = (objectRoot.Position - flagRoot.Position).Magnitude

							if distance <= radius then
								object:SetAttribute("TeamOwner", flagOwner)
								paintObject(object)
								break
							end
						end
					end
				end
			end
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

	if not folder then
		warn("[TerritoryManager] Workspace.Base_objects not found")
		return
	end

	folder.ChildAdded:Connect(function(child)
		task.wait(0.1)
		setupObject(child)
	end)
end

return TerritoryManager