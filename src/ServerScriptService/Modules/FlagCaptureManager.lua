local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FlagManager = require(script.Parent.FlagManager)
local VehicleAccess = require(script.Parent.VehicleAccess)

local FlagCaptureManager = {}

local UPDATE_INTERVAL = 0.1
local DEFAULT_DECAY_MULTIPLIER = 0.5

local started = false
local accumulator = 0
local previousOwners = {}

local function getNotificationRemote()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local remote = remotes:FindFirstChild("FlagCaptureNotification")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "FlagCaptureNotification"
		remote.Parent = remotes
	end

	return remote
end


local function getFlagMain(flag)
	local main = flag:FindFirstChild("Main")
	if main and main:IsA("BasePart") then
		return main
	end
	return flag.PrimaryPart or flag:FindFirstChildWhichIsA("BasePart")
end

local function getAliveRoot(player)
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end

	return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

local function isPlayerInsideFlag(player, flag)
	local root = getAliveRoot(player)
	local main = getFlagMain(flag)

	if not root or not main then
		return false
	end

	local radius = FlagManager.GetOwnershipRadius(flag)
	return (root.Position - main.Position).Magnitude <= radius
end

local function getShowName(flag)
	local showName = flag:GetAttribute("Show_name")
	if typeof(showName) == "string" and showName ~= "" then
		return showName
	end
	return flag.Name
end

local function notifyTeamOutsideRadius(flag, teamId, kind)
	teamId = tonumber(teamId)
	if not teamId or teamId <= 0 then
		return
	end

	local remote = getNotificationRemote()
	local regionName = getShowName(flag)

	for _, player in ipairs(Players:GetPlayers()) do
		local playerTeam = tonumber(VehicleAccess.GetPlayerTeamOwner(player))

		if playerTeam == teamId and not isPlayerInsideFlag(player, flag) then
			remote:FireClient(player, {
				Kind = kind,
				RegionName = regionName,
				TeamOwner = teamId,
			})
		end
	end
end

local function getTeamsInsideFlag(flag)
	local main = getFlagMain(flag)
	if not main then return {} end

	local radius = FlagManager.GetOwnershipRadius(flag)
	local teams = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local root = getAliveRoot(player)
		if root and (root.Position - main.Position).Magnitude <= radius then
			local teamOwner = tonumber(VehicleAccess.GetPlayerTeamOwner(player))
			if teamOwner and teamOwner > 0 then
				teams[teamOwner] = (teams[teamOwner] or 0) + 1
			end
		end
	end

	return teams
end

local function getSingleTeam(teams)
	local found = nil
	for teamId, count in pairs(teams) do
		if count > 0 then
			if found ~= nil then
				return nil
			end
			found = teamId
		end
	end
	return found
end

local function resetCapture(flag)
	flag:SetAttribute("CaptureProgress", 0)
	flag:SetAttribute("CaptureTeam", 0)
	flag:SetAttribute("Contested", false)
end

local function decayProgress(flag, dt)
	local progress = math.max(0, tonumber(flag:GetAttribute("CaptureProgress")) or 0)
	if progress <= 0 then
		flag:SetAttribute("CaptureProgress", 0)
		flag:SetAttribute("CaptureTeam", 0)
		return
	end

	local decayMultiplier =
		tonumber(flag:GetAttribute("Capture_decay_multiplier"))
		or DEFAULT_DECAY_MULTIPLIER

	progress = math.max(0, progress - dt * math.max(0, decayMultiplier))
	flag:SetAttribute("CaptureProgress", progress)

	if progress <= 0 then
		flag:SetAttribute("CaptureTeam", 0)
	end
end

local function updateDestroyedState(flag)
	local currentHealth =
		math.max(0, tonumber(flag:GetAttribute("Current_health")) or 0)

	local destroyed = flag:GetAttribute("Destroyed") == true

	if currentHealth <= 0 then
		if not destroyed then
			FlagManager.SetDestroyed(flag, true)
			print("[FlagCapture] FLAG DOWN:", flag.Name)
		end
		return true
	end

	if destroyed then
		flag:SetAttribute("Destroyed", false)
		resetCapture(flag)
		FlagManager.PaintFlag(flag)
		print("[FlagCapture] FLAG RESTORED:", flag.Name)
	end

	return false
end

local function processFlag(flag, dt)
	if not flag.Parent or not FlagManager.IsFlag(flag) then
		return
	end

	if updateDestroyedState(flag) then
		resetCapture(flag)
		return
	end

	if FlagManager.IsBaseFlag(flag) then
		resetCapture(flag)
		return
	end

	local teams = getTeamsInsideFlag(flag)
	local capturingTeam = getSingleTeam(teams)

	if not capturingTeam then
		local teamKinds = 0
		for _, count in pairs(teams) do
			if count > 0 then
				teamKinds += 1
			end
		end

		if teamKinds > 1 then
			flag:SetAttribute("Contested", true)
			return
		end

		flag:SetAttribute("Contested", false)
		decayProgress(flag, dt)
		return
	end

	flag:SetAttribute("Contested", false)

	local owner = tonumber(FlagManager.GetTeamOwner(flag)) or 0
	if owner == capturingTeam then
		resetCapture(flag)
		return
	end

	local captureTeam = tonumber(flag:GetAttribute("CaptureTeam")) or 0
	local progress = math.max(0, tonumber(flag:GetAttribute("CaptureProgress")) or 0)

	if captureTeam ~= 0 and captureTeam ~= capturingTeam then
		progress = 0
	end

	captureTeam = capturingTeam
	progress += dt

	flag:SetAttribute("CaptureTeam", captureTeam)
	flag:SetAttribute("CaptureProgress", progress)

	local captureTime = FlagManager.GetCaptureTime(flag)
	if progress < captureTime then
		return
	end

	if owner ~= 0 then
		previousOwners[flag] = owner

		FlagManager.SetTeamOwner(flag, 0)
		flag:SetAttribute("CaptureProgress", 0)
		flag:SetAttribute("CaptureTeam", capturingTeam)

		print("[FlagCapture] NEUTRALIZED:", flag.Name, "by team", capturingTeam)
	else
		local oldOwner = previousOwners[flag]

		FlagManager.SetTeamOwner(flag, capturingTeam)
		resetCapture(flag)

		local maxHealth =
			math.max(0, tonumber(flag:GetAttribute("Max_health")) or 0)
		if maxHealth > 0 then
			flag:SetAttribute("Current_health", maxHealth)
		end

		notifyTeamOutsideRadius(flag, capturingTeam, "Captured")

		if oldOwner and tonumber(oldOwner) ~= tonumber(capturingTeam) then
			notifyTeamOutsideRadius(flag, oldOwner, "Lost")
		end

		previousOwners[flag] = capturingTeam

		print("[FlagCapture] CAPTURED:", flag.Name, "by team", capturingTeam)
	end
end

function FlagCaptureManager.Start()
	if started then return end
	started = true
	getNotificationRemote()

	for _, flag in ipairs(FlagManager.GetAllFlags()) do
		local owner = tonumber(FlagManager.GetTeamOwner(flag)) or 0
		if owner > 0 then
			previousOwners[flag] = owner
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < UPDATE_INTERVAL then
			return
		end

		local step = accumulator
		accumulator = 0

		for _, flag in ipairs(FlagManager.GetAllFlags()) do
			processFlag(flag, step)
		end
	end)

	print("[FlagCapture] Started")
end

return FlagCaptureManager
