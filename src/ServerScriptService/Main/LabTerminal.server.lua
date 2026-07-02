local Modules = script.Parent.Parent:WaitForChild("Modules")

local LabTerminalManager = require(Modules:WaitForChild("LabTerminalManager"))

LabTerminalManager.SetupAll()
LabTerminalManager.StartAutoSetup()
LabTerminalManager.StartRemoteListener()