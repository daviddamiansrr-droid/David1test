--!strict
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Shared")

local Client = script.Parent
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Hud = require(Client.Hud)
local Honeycomb = require(Client.Honeycomb)
local PlotFx = require(Client.PlotFx)
local VacFx = require(Client.VacFx)
local VacController = require(Client.VacController)
local Jetpack = require(Client.Jetpack)
local ShopUI = require(Client.ShopUI)
local SlimeJuice = require(Client.SlimeJuice)
local PortalSwirl = require(Client.PortalSwirl)
local CoinStation = require(Client.CoinStation)
local HoverboardSound = require(Client.HoverboardSound)

Hud.init()
ShopUI.init()
VacFx.init()
VacController.init()
Jetpack.init()
PortalSwirl.init()
CoinStation.init()
HoverboardSound.init()
task.spawn(Honeycomb.init)
task.spawn(PlotFx.init)
task.spawn(SlimeJuice.init)

-- HUD buttons. Index / Hoverboard / Settings are left as signals
-- (Hud.IndexPressed etc.) for whatever systems your place already has.
Hud.ShopPressed:Connect(function()
	ShopUI.open("Vac")
end)
Hud.HomePressed:Connect(function()
	Remotes.event("Travel"):FireServer("home")
end)
Hud.JetpackPressed:Connect(function()
	Hud.toast("Hold jump in the air to fly", "info")
end)
