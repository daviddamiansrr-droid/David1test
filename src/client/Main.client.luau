--!strict
if not game:IsLoaded() then
	game.Loaded:Wait()
end
game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Client = script.Parent

local Hud = require(Client.Hud)
local Honeycomb = require(Client.Honeycomb)
local PlotFx = require(Client.PlotFx)
local VacFx = require(Client.VacFx)
local VacController = require(Client.VacController)
local Jetpack = require(Client.Jetpack)
local ShopUI = require(Client.ShopUI)
local SlimeJuice = require(Client.SlimeJuice)

Hud.init()
ShopUI.init()
VacFx.init()
VacController.init()
Jetpack.init()
task.spawn(Honeycomb.init)
task.spawn(PlotFx.init)
task.spawn(SlimeJuice.init)
