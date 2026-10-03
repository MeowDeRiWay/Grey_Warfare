local Workspace = game:GetService("Workspace")

local ScreenManager = {}

-- GENERAL SCREEN MANAGER
-- One place for all world screens.
--
-- Current role:
--   Team_supply = true -> show nearby Warehouse cargo.
--
-- Future roles (lab, vehicle terminal, etc.) should be added here
-- as separate role handlers instead of creating separate screen managers.
local DEFAULT_WH_RADIUS = 200
local REFRESH_INTERVAL = 0.5
local trackedScreens = {}

local function getPart(model)
	local part = model:FindFirstChild("Part", true)
	if part and part:IsA("BasePart") then return part end
	if model.PrimaryPart then return model.PrimaryPart end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getPosition(model)
	local part = getPart(model)
	return part and part.Position or nil
end

local function isWarehouse(model)
	return model:IsA("Model") and model:GetAttribute("ObjectType") == "Warehouse"
end

local function isTeamSupplyScreen(model)
	return model:IsA("Model")
		and model:GetAttribute("Screen") == true
		and model:GetAttribute("Team_supply") == true
end

local function findNearestWarehouse(screen)
	local origin = getPosition(screen)
	if not origin then return nil end

	local radius = tonumber(screen:GetAttribute("WH_radius")) or DEFAULT_WH_RADIUS
	if radius <= 0 then return nil end

	local baseObjects = Workspace:FindFirstChild("Base_objects")
	if not baseObjects then return nil end

	local best, bestDistance = nil, radius
	for _, object in ipairs(baseObjects:GetDescendants()) do
		if isWarehouse(object) then
			local pos = getPosition(object)
			if pos then
				local distance = (pos - origin).Magnitude
				if distance <= bestDistance then
					best, bestDistance = object, distance
				end
			end
		end
	end
	return best
end

local function formatNumber(value)
	value = math.max(0, tonumber(value) or 0)
	if math.abs(value - math.round(value)) < 0.001 then
		return tostring(math.round(value))
	end
	return string.format("%.1f", value)
end

local function createGui(part)
	local old = part:FindFirstChild("WarehouseScreenGui")
	if old then old:Destroy() end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "WarehouseScreenGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(14, 18, 22)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.06)
	title.Size = UDim2.fromScale(0.9, 0.2)
	title.Font = Enum.Font.Code
	title.Text = "СКЛАД БАЗИ"
	title.TextColor3 = Color3.fromRGB(220, 230, 235)
	title.TextScaled = true
	title.Parent = bg

	local cargo = Instance.new("TextLabel")
	cargo.BackgroundTransparency = 1
	cargo.Position = UDim2.fromScale(0.05, 0.31)
	cargo.Size = UDim2.fromScale(0.9, 0.4)
	cargo.Font = Enum.Font.Code
	cargo.Text = "ВАНТАЖ\nПОШУК..."
	cargo.TextColor3 = Color3.fromRGB(245, 245, 245)
	cargo.TextScaled = true
	cargo.Parent = bg

	local percent = Instance.new("TextLabel")
	percent.BackgroundTransparency = 1
	percent.Position = UDim2.fromScale(0.05, 0.75)
	percent.Size = UDim2.fromScale(0.9, 0.15)
	percent.Font = Enum.Font.Code
	percent.TextColor3 = Color3.fromRGB(180, 190, 195)
	percent.TextScaled = true
	percent.Parent = bg

	return gui, cargo, percent
end

local function updateScreen(screen, state)
	if not screen.Parent then return false end

	local warehouse = findNearestWarehouse(screen)
	if not warehouse then
		state.Cargo.Text = "ВАНТАЖ\nСКЛАД НЕ ЗНАЙДЕНО"
		state.Percent.Text = ""
		return true
	end

	local current = tonumber(warehouse:GetAttribute("Cargo_cur")) or 0
	local maximum = tonumber(warehouse:GetAttribute("Cargo_max")) or 0
	state.Cargo.Text = "ВАНТАЖ\n" .. formatNumber(current) .. " / " .. formatNumber(maximum)

	if maximum > 0 then
		state.Percent.Text = string.format("%.1f%%", math.clamp(current / maximum * 100, 0, 100))
	else
		state.Percent.Text = ""
	end
	return true
end

local function setupScreen(screen)
	if trackedScreens[screen] or not isTeamSupplyScreen(screen) then return end
	local part = getPart(screen)
	if not part then
		warn("[ScreenManager] No Part:", screen:GetFullName())
		return
	end

	local gui, cargo, percent = createGui(part)
	local state = {Gui = gui, Cargo = cargo, Percent = percent}
	trackedScreens[screen] = state
	updateScreen(screen, state)
end

local function cleanup(screen)
	local state = trackedScreens[screen]
	if not state then return end
	if state.Gui then state.Gui:Destroy() end
	trackedScreens[screen] = nil
end

function ScreenManager.SetupAll()
	for _, object in ipairs(Workspace:GetDescendants()) do
		if isTeamSupplyScreen(object) then setupScreen(object) end
	end
end

function ScreenManager.StartAutoSetup()
	Workspace.DescendantAdded:Connect(function(object)
		if isTeamSupplyScreen(object) then task.defer(setupScreen, object) end
	end)

	Workspace.DescendantRemoving:Connect(function(object)
		if trackedScreens[object] then cleanup(object) end
	end)

	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL)
			for screen, state in pairs(trackedScreens) do
				if not updateScreen(screen, state) then cleanup(screen) end
			end
		end
	end)
end

return ScreenManager
