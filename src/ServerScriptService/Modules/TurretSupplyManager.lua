local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local WarehouseManager = require(script.Parent.WarehouseManager)
local RocketLauncherController = require(script.Parent.RocketLauncherController)

local TurretSupplyManager = {}

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"
local ACTIVE_VEHICLES_FOLDER_NAME = "ActiveVehicles"

local DEFAULT_SUPPLY_TIME = 5
local DEFAULT_TOUCH_RADIUS = 8

local progressByTurret = {}
local started = false

local function getMain(model)
	if not model then
		return nil
	end

	local main = model:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getPart(model, name)
	if not model then
		return nil
	end

	local part = model:FindFirstChild(name, true)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

local function getTeamOwner(model)
	return tonumber(model and model:GetAttribute("TeamOwner")) or 0
end

local function sameTeam(a, b)
	local teamA = getTeamOwner(a)
	local teamB = getTeamOwner(b)

	return teamA ~= 0
		and teamB ~= 0
		and teamA == teamB
end

local function isModelNearPart(model, part)
	local main = getMain(model)
	if not main or not part then
		return false
	end

	local radius = tonumber(part:GetAttribute("Transfer_radius"))
		or tonumber(part:GetAttribute("Touch_radius"))
		or DEFAULT_TOUCH_RADIUS

	if (main.Position - part.Position).Magnitude <= radius then
		return true
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }

	local ok, touchingParts = pcall(function()
		return Workspace:GetPartsInPart(part, params)
	end)

	return ok and #touchingParts > 0
end

local function getMountedTurrets(vehicle)
	local result = {}
	local mountedModules = vehicle:FindFirstChild("MountedModules")

	if not mountedModules then
		return result
	end

	for _, module in ipairs(mountedModules:GetChildren()) do
		if module:IsA("Model")
			and (
				module:GetAttribute("ModuleRole") == "Turret"
				or module:GetAttribute("Turret") == true
			)
		then
			table.insert(result, module)
		end
	end

	return result
end

local function getSupplyProviders()
	local providers = {}

	local baseObjects = Workspace:FindFirstChild(BASE_OBJECTS_FOLDER_NAME)
	if baseObjects then
		for _, object in ipairs(baseObjects:GetChildren()) do
			if object:IsA("Model")
				and object:GetAttribute("ObjectType") == "SupplyStation"
			then
				table.insert(providers, object)
			end
		end
	end

	local activeVehicles = Workspace:FindFirstChild(ACTIVE_VEHICLES_FOLDER_NAME)
	if activeVehicles then
		for _, vehicle in ipairs(activeVehicles:GetChildren()) do
			local mountedModules = vehicle:FindFirstChild("MountedModules")

			if mountedModules then
				for _, module in ipairs(mountedModules:GetChildren()) do
					if module:IsA("Model")
						and module:GetAttribute("ModuleRole") == "SupplyStation"
					then
						table.insert(providers, module)
					end
				end
			end
		end
	end

	return providers
end

local function findProviderNearVehicle(vehicle)
	for _, provider in ipairs(getSupplyProviders()) do
		if provider.Parent and sameTeam(vehicle, provider) then
			local addSupply = getPart(provider, "add_supply")

			if addSupply and isModelNearPart(vehicle, addSupply) then
				return provider
			end
		end
	end

	return nil
end

local function tryBuyOneMagazine(turret, provider)
	local currentMagazines =
		tonumber(turret:GetAttribute("Current_magazines")) or 0

	local maxMagazines =
		tonumber(turret:GetAttribute("Max_magazines")) or 0

	if maxMagazines <= 0 or currentMagazines >= maxMagazines then
		return false
	end

	local cargoCost =
		tonumber(turret:GetAttribute("Magazine_cargo_cost")) or 1

	cargoCost = math.max(0, cargoCost)

	if cargoCost > 0 then
		if not WarehouseManager.CanPayCargo(provider, cargoCost) then
			return false
		end

		if not WarehouseManager.PayCargo(provider, cargoCost) then
			return false
		end
	end

	turret:SetAttribute(
		"Current_magazines",
		math.min(maxMagazines, currentMagazines + 1)
	)

	return true
end

local function processVehicle(vehicle, dt)
	local turrets = getMountedTurrets(vehicle)

	if #turrets == 0 then
		return
	end

	local provider = findProviderNearVehicle(vehicle)

	if not provider then
		for _, turret in ipairs(turrets) do
			progressByTurret[turret] = 0
		end
		return
	end

	local supplyTime =
		tonumber(provider:GetAttribute("Supply_time"))
		or DEFAULT_SUPPLY_TIME

	if supplyTime <= 0 then
		supplyTime = DEFAULT_SUPPLY_TIME
	end

	for _, turret in ipairs(turrets) do
		if RocketLauncherController.IsRocketLauncher(turret) then
			RocketLauncherController.RegisterLauncher(turret, false)

			local currentRockets =
				RocketLauncherController.GetLoadedCount(turret)

			local maxRockets =
				RocketLauncherController.GetMaxCount(turret)

			if maxRockets <= 0 or currentRockets >= maxRockets then
				progressByTurret[turret] = 0
				continue
			end

			-- For rocket packs Reload_time belongs to the launcher itself:
			-- seconds needed to insert ONE rocket into ONE empty Ammo_module.
			local rocketReloadTime =
				tonumber(turret:GetAttribute("Reload_time"))
				or 1

			if rocketReloadTime <= 0 then
				rocketReloadTime = 1
			end

			local progress =
				(progressByTurret[turret] or 0)
				+ dt

			while progress >= rocketReloadTime do
				if not RocketLauncherController.TryRefillOne(
					turret,
					provider
				) then
					progress = rocketReloadTime
					break
				end

				progress -= rocketReloadTime

				currentRockets =
					RocketLauncherController.GetLoadedCount(turret)

				if currentRockets >= maxRockets then
					progress = 0
					break
				end
			end

			progressByTurret[turret] = progress
		else
			local currentMagazines =
				tonumber(turret:GetAttribute("Current_magazines")) or 0

			local maxMagazines =
				tonumber(turret:GetAttribute("Max_magazines")) or 0

			if maxMagazines <= 0 or currentMagazines >= maxMagazines then
				progressByTurret[turret] = 0
				continue
			end

			local progress = (progressByTurret[turret] or 0) + dt

			while progress >= supplyTime do
				if not tryBuyOneMagazine(turret, provider) then
					progress = supplyTime
					break
				end

				progress -= supplyTime

				currentMagazines =
					tonumber(turret:GetAttribute("Current_magazines")) or 0

				if currentMagazines >= maxMagazines then
					progress = 0
					break
				end
			end

			progressByTurret[turret] = progress
		end
	end
end

function TurretSupplyManager.Start()
	if started then
		return
	end

	started = true

	RunService.Heartbeat:Connect(function(dt)
		local activeVehicles =
			Workspace:FindFirstChild(ACTIVE_VEHICLES_FOLDER_NAME)

		if not activeVehicles then
			return
		end

		for _, vehicle in ipairs(activeVehicles:GetChildren()) do
			if vehicle:IsA("Model") then
				processVehicle(vehicle, dt)
			end
		end
	end)
end

return TurretSupplyManager
