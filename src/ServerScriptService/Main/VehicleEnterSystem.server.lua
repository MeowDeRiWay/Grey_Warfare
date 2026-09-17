local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = script.Parent.Parent:WaitForChild("Modules")
local VehicleAccess = require(Modules:WaitForChild("VehicleAccess"))

local ENTER_DISTANCE = 6
local REQUEST_COOLDOWN = 0.35

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local enterRemote = remotes:FindFirstChild("VehicleEnterRequest")
if not enterRemote then
	enterRemote = Instance.new("RemoteEvent")
	enterRemote.Name = "VehicleEnterRequest"
	enterRemote.Parent = remotes
end

local lastRequest = {}
local seatConnections = {}

-- =========================================================
-- HELPERS
-- =========================================================

local function getDriverSeat(vehicle)
	if not vehicle then
		return nil
	end

	local seat = vehicle:FindFirstChild("Driver_seat", true)
	if seat and (seat:IsA("VehicleSeat") or seat:IsA("Seat")) then
		return seat
	end

	return nil
end

local function pointToModelDistance(vehicle, worldPoint)
	local boxCFrame, boxSize = vehicle:GetBoundingBox()
	local localPoint = boxCFrame:PointToObjectSpace(worldPoint)
	local half = boxSize * 0.5

	local closest = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)

	return (localPoint - closest).Magnitude
end

local function isActiveVehicle(vehicle)
	if typeof(vehicle) ~= "Instance" or not vehicle:IsA("Model") then
		return false
	end

	local folder = Workspace:FindFirstChild("ActiveVehicles")
	return folder ~= nil and vehicle.Parent == folder
end

local function canPlayerDriveVehicle(player, vehicle)
	local ownerUserId = vehicle:GetAttribute("OwnerUserId")
	if ownerUserId ~= nil and tonumber(ownerUserId) ~= player.UserId then
		return false
	end

	local vehicleTeamOwner = vehicle:GetAttribute("TeamOwner")
	local playerTeamOwner = VehicleAccess.GetPlayerTeamOwner(player)

	if vehicleTeamOwner ~= nil and playerTeamOwner ~= nil then
		if tonumber(vehicleTeamOwner) ~= tonumber(playerTeamOwner) then
			return false
		end
	end

	return true
end

-- =========================================================
-- REMOVE OLD ENTER MECHANICS
-- =========================================================

local function removeLegacyPrompts(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("ProximityPrompt") then
			if item.Name == "HelicopterEnterPrompt"
				or item.ActionText == "Enter / Exit"
			then
				item:Destroy()
			end
		end
	end
end

local function lockEmptySeat(seat)
	if not seat or not seat.Parent then
		return
	end

	-- ВАЖЛИВО:
	-- Disabled=true прибирає вбудовану Roblox-посадку від простого дотику.
	-- Коли гравець натисне E, ми коротко вмикаємо Seat,
	-- садимо його через :Sit(), а поки він сидить Seat лишається активним
	-- для Throttle/Steer.
	if seat.Occupant == nil then
		seat.Disabled = true
	end

	seat.CanTouch = false
end


local function getNumberAttr(primary, secondary, name, default)
	local value = primary and primary:GetAttribute(name)
	if value == nil and secondary then
		value = secondary:GetAttribute(name)
	end
	if value == nil then
		return default
	end
	return tonumber(value) or default
end

local function applySeatOffset(vehicle, seat)
	if not vehicle or not seat or not seat.Parent or not seat.Occupant then
		return
	end

	-- Roblox creates SeatWeld asynchronously after :Sit().
	-- Wait briefly, then shift that weld instead of moving the seat/model itself.
	task.defer(function()
		local weld = nil
		for _ = 1, 12 do
			if not seat.Parent or not seat.Occupant then
				return
			end

			weld = seat:FindFirstChild("SeatWeld")
			if weld and weld:IsA("Weld") then
				break
			end
			task.wait()
		end

		if not weld or not weld:IsA("Weld") then
			return
		end

		-- applySeatOffset can be called both by the Occupant signal and by the E-entry path.
		-- Never stack the offset twice on the same SeatWeld. A new sit creates a new weld,
		-- so the marker naturally resets on the next entry.
		if weld:GetAttribute("SeatOffsetApplied") == true then
			return
		end
		weld:SetAttribute("SeatOffsetApplied", true)

		-- Values can live on Driver_seat or on the vehicle model.
		-- Defaults are tuned for the compact Soldier rig used by this project.
		local x = getNumberAttr(seat, vehicle, "Seat_offset_x", 0)
		local y = getNumberAttr(seat, vehicle, "Seat_offset_y", 0)
		local z = getNumberAttr(seat, vehicle, "Seat_offset_z", -0.9)
		local pitch = math.rad(getNumberAttr(seat, vehicle, "Seat_pitch", 0))
		local yaw = math.rad(getNumberAttr(seat, vehicle, "Seat_yaw", 0))
		local roll = math.rad(getNumberAttr(seat, vehicle, "Seat_roll", 0))

		weld.C0 = weld.C0
			* CFrame.new(x, y, z)
			* CFrame.Angles(pitch, yaw, roll)
	end)
end

local function watchVehicle(vehicle)
	if not vehicle:IsA("Model") then
		return
	end

	removeLegacyPrompts(vehicle)

	-- Якщо старий HelicopterDriveController створить prompt ПІСЛЯ нас,
	-- видаляємо його одразу ж.
	vehicle.DescendantAdded:Connect(function(item)
		if item:IsA("ProximityPrompt") then
			if item.Name == "HelicopterEnterPrompt"
				or item.ActionText == "Enter / Exit"
			then
				task.defer(function()
					if item.Parent then
						item:Destroy()
					end
				end)
			end
		end
	end)

	local seat = getDriverSeat(vehicle)
	if not seat then
		task.defer(function()
			task.wait(0.1)
			seat = getDriverSeat(vehicle)
			if seat then
				watchVehicle(vehicle)
			end
		end)
		return
	end

	if seatConnections[seat] then
		return
	end

	lockEmptySeat(seat)

	seatConnections[seat] = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Parent then
			local connection = seatConnections[seat]
			if connection then
				connection:Disconnect()
			end
			seatConnections[seat] = nil
			return
		end

		if seat.Occupant == nil then
			-- Вийшов із машини -> знову блокуємо touch-enter.
			task.defer(function()
				if seat.Parent and seat.Occupant == nil then
					seat.Disabled = true
					seat.CanTouch = false
				end
			end)
		else
			-- Поки водій сидить, Seat має бути активним для керування.
			seat.Disabled = false
			applySeatOffset(vehicle, seat)
		end
	end)

	-- VehicleSpawner can seat the owner before this watcher is attached.
	-- In that case the Occupant change was already missed, so handle the current state once.
	if seat.Occupant ~= nil then
		seat.Disabled = false
		applySeatOffset(vehicle, seat)
	end
end

local function prepareVehicles()
	local folder = Workspace:FindFirstChild("ActiveVehicles")
	if not folder then
		folder = Workspace:WaitForChild("ActiveVehicles")
	end

	for _, vehicle in ipairs(folder:GetChildren()) do
		watchVehicle(vehicle)
	end

	folder.ChildAdded:Connect(function(vehicle)
		task.defer(function()
			watchVehicle(vehicle)
		end)
	end)
end

-- =========================================================
-- ENTER BY E ONLY
-- =========================================================

enterRemote.OnServerEvent:Connect(function(player, vehicle)
	local now = os.clock()
	local previous = lastRequest[player]

	if previous and now - previous < REQUEST_COOLDOWN then
		return
	end
	lastRequest[player] = now

	if not isActiveVehicle(vehicle) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		return
	end

	if humanoid.Health <= 0 or humanoid.SeatPart then
		return
	end

	local seat = getDriverSeat(vehicle)
	if not seat or seat.Occupant ~= nil then
		return
	end

	if not canPlayerDriveVehicle(player, vehicle) then
		return
	end

	local distance = pointToModelDistance(vehicle, root.Position)
	if distance > ENTER_DISTANCE then
		return
	end

	-- Дозволяємо посадку ТІЛЬКИ на момент серверного E-запиту.
	seat.Disabled = false
	seat:Sit(humanoid)
	applySeatOffset(vehicle, seat)

	-- Якщо з якоїсь причини посадка не сталася — знову блокуємо seat.
	task.delay(0.15, function()
		if seat.Parent and seat.Occupant == nil then
			seat.Disabled = true
			seat.CanTouch = false
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

task.defer(prepareVehicles)
