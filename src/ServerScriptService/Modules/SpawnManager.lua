local Workspace = game:GetService("Workspace")

local FlagManager = require(script.Parent.FlagManager)

local SpawnManager = {}

local UPDATE_INTERVAL = 1
local TELEPORT_HEIGHT = 3

local dynamicSpawns = {}
local started = false

local function isSpawnObject(object)
	return (object:IsA("BasePart") or object:IsA("Model"))
		and object:GetAttribute("Spawn_point") == true
end

local function getRootPart(object)
	if object:IsA("BasePart") then
		return object
	end

	if object:IsA("Model") then
		local root = object.PrimaryPart
			or object:FindFirstChild("Main")
			or object:FindFirstChildWhichIsA("BasePart", true)

		if root and root:IsA("BasePart") then
			return root
		end
	end

	return nil
end

local function getSpawnName(object)
	local name = object:GetAttribute("Spawn_name")
	if typeof(name) == "string" and name ~= "" then
		return name
	end

	return object.Name
end

local function setTeam(object, teamOwner)
	teamOwner = tonumber(teamOwner) or 0

	if object:GetAttribute("Team") ~= teamOwner then
		object:SetAttribute("Team", teamOwner)
	end

	if object:GetAttribute("Team_color") ~= teamOwner then
		object:SetAttribute("Team_color", teamOwner)
	end
end

local function findOwningFlag(object)
	local root = getRootPart(object)
	if not root then
		return nil
	end

	local selectedFlag = nil
	local selectedDistance = math.huge

	for _, flag in ipairs(FlagManager.GetAllFlags()) do
		local flagRoot = getRootPart(flag)

		if flagRoot then
			local radius = FlagManager.GetOwnershipRadius(flag)
			local distance = (root.Position - flagRoot.Position).Magnitude

			if distance <= radius and distance < selectedDistance then
				selectedFlag = flag
				selectedDistance = distance
			end
		end
	end

	return selectedFlag
end

local function updateDynamicSpawn(object)
	if not object.Parent or not isSpawnObject(object) then
		dynamicSpawns[object] = nil
		return
	end

	local flag = findOwningFlag(object)

	if not flag or FlagManager.IsDestroyed(flag) then
		setTeam(object, 0)
		return
	end

	setTeam(object, tonumber(FlagManager.GetTeamOwner(flag)) or 0)
end

function SpawnManager.SetupSpawn(object)
	if not isSpawnObject(object) then
		return
	end

	if not getRootPart(object) then
		warn("[SpawnManager] Spawn has no BasePart:", object:GetFullName())
		return
	end

	if object:GetAttribute("Main") == nil then
		object:SetAttribute("Main", false)
	end

	if object:GetAttribute("Spawn_name") == nil then
		object:SetAttribute("Spawn_name", object.Name)
	end

	local team = tonumber(object:GetAttribute("Team")) or 0
	setTeam(object, team)

	-- Team = 0 at setup means this point follows the flag whose
	-- OwnershipRadius contains it. After that Team may become 1/2,
	-- but it remains registered as dynamic.
	if team == 0 then
		dynamicSpawns[object] = true
		updateDynamicSpawn(object)
	else
		dynamicSpawns[object] = nil
	end
end

function SpawnManager.SetupAll()
	for _, object in ipairs(Workspace:GetDescendants()) do
		if isSpawnObject(object) then
			SpawnManager.SetupSpawn(object)
		end
	end
end

function SpawnManager.GetAll()
	local result = {}

	for _, object in ipairs(Workspace:GetDescendants()) do
		if isSpawnObject(object) then
			table.insert(result, object)
		end
	end

	return result
end

function SpawnManager.GetAvailable(teamOwner, mainOnly)
	teamOwner = tonumber(teamOwner) or 0
	local result = {}

	for _, object in ipairs(SpawnManager.GetAll()) do
		local team = tonumber(object:GetAttribute("Team")) or 0
		local isMain = object:GetAttribute("Main") == true

		if team == teamOwner and (not mainOnly or isMain) then
			table.insert(result, object)
		end
	end

	table.sort(result, function(a, b)
		return getSpawnName(a) < getSpawnName(b)
	end)

	return result
end

function SpawnManager.GetMain(teamOwner)
	local spawns = SpawnManager.GetAvailable(teamOwner, true)
	return spawns[1]
end

function SpawnManager.TeleportPlayer(player, spawnObject)
	if not player or not spawnObject then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local spawnRoot = getRootPart(spawnObject)

	if not root or not root:IsA("BasePart") or not spawnRoot then
		return false
	end

	root.CFrame = spawnRoot.CFrame + Vector3.new(0, TELEPORT_HEIGHT, 0)
	return true
end

function SpawnManager.SpawnAtMain(player)
	local teamOwner = tonumber(player:GetAttribute("TeamOwner")) or 0
	if teamOwner <= 0 then
		return false
	end

	local mainSpawn = SpawnManager.GetMain(teamOwner)

	if not mainSpawn then
		warn("[SpawnManager] No Main spawn for Team", teamOwner)
		return false
	end

	return SpawnManager.TeleportPlayer(player, mainSpawn)
end

function SpawnManager.UpdateDynamic()
	for object in pairs(dynamicSpawns) do
		updateDynamicSpawn(object)
	end
end

function SpawnManager.Start()
	if started then
		return
	end
	started = true

	SpawnManager.SetupAll()
	SpawnManager.UpdateDynamic()

	Workspace.DescendantAdded:Connect(function(object)
		task.defer(function()
			if isSpawnObject(object) then
				SpawnManager.SetupSpawn(object)
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL)
			SpawnManager.UpdateDynamic()
		end
	end)

	print("[SpawnManager] Started")
end

return SpawnManager
