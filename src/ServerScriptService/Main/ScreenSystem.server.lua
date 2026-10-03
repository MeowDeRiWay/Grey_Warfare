local Modules = script.Parent.Parent:WaitForChild("Modules")
local ScreenManager = require(Modules:WaitForChild("ScreenManager"))

ScreenManager.SetupAll()
ScreenManager.StartAutoSetup()
