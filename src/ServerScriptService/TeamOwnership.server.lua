local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")

local FlagManager = require(Modules:WaitForChild("FlagManager"))
local TerritoryManager = require(Modules:WaitForChild("TerritoryManager"))
local FlagCaptureManager = require(Modules:WaitForChild("FlagCaptureManager"))
local VehicleTerminalManager = require(Modules:WaitForChild("VehicleTerminalManager"))
local WarehouseManager = require(Modules:WaitForChild("WarehouseManager"))

FlagManager.SetupAllFlags()
FlagManager.StartAutoSetup()
FlagCaptureManager.Start()

TerritoryManager.SetupAllObjects()
TerritoryManager.StartAutoSetup()
TerritoryManager.StartLoop()

WarehouseManager.SetupAll()
WarehouseManager.StartAutoSetup()
WarehouseManager.StartLoop()

VehicleTerminalManager.SetupAll()
VehicleTerminalManager.StartAutoSetup()
VehicleTerminalManager.StartRemoteListener()

print("[TeamOwnership] Started")