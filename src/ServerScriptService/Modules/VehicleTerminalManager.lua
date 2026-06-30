local Workspace = game:GetService("Workspace")

local VehicleTerminalManager = {}

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"

local PROMPT_ACTION_TEXT = "Open"
local PROMPT_OBJECT_TEXT = "Vehicle Terminal"
local PROMPT_KEY = Enum.KeyCode.E

local function getBaseObjectsFolder()
	return Workspace:FindFirstChild(BASE_OBJECTS_FOLDER_NAME)
end

local function isVehicleTerminal(object)
	return object:IsA("Model") and object:GetAttribute("ObjectType") == "VehicleTerminal"
end

local function getScreen(object)
	local screen = object:FindFirstChild("Screen", true)

	if screen and screen:IsA("BasePart") then
		return screen
	end

	return nil
end

local function setupPrompt(object)
	if not isVehicleTerminal(object) then
		return
	end

	local screen = getScreen(object)

	if not screen then
		warn("[VehicleTerminalManager] Screen not found:", object:GetFullName())
		return
	end

	local oldPrompt = screen:FindFirstChild("VehicleTerminalPrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VehicleTerminalPrompt"
	prompt.ActionText = PROMPT_ACTION_TEXT
	prompt.ObjectText = PROMPT_OBJECT_TEXT
	prompt.KeyboardKeyCode = PROMPT_KEY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = screen

	prompt.Triggered:Connect(function(player)
		local teamOwner = object:GetAttribute("TeamOwner") or 0

		print("[VehicleTerminal] Open requested by", player.Name)
		print("[VehicleTerminal] Terminal:", object.Name)
		print("[VehicleTerminal] TeamOwner:", teamOwner)

		-- Тут потім відкриємо GUI вибору техніки
	end)
end

function VehicleTerminalManager.SetupAll()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[VehicleTerminalManager] Workspace.Base_objects not found")
		return
	end

	for _, object in ipairs(folder:GetChildren()) do
		setupPrompt(object)
	end
end

function VehicleTerminalManager.StartAutoSetup()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[VehicleTerminalManager] Workspace.Base_objects not found")
		return
	end

	folder.ChildAdded:Connect(function(child)
		task.wait(0.1)
		setupPrompt(child)
	end)
end

return VehicleTerminalManager