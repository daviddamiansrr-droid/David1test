--!strict
-- Server bootstrap. Order matters: collision groups -> map -> services -> players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes) -- creates the remotes
local Collision = require(script.Parent.Collision)
local MapBuilder = require(script.Parent.MapBuilder)
local DataService = require(script.Parent.DataService)
local StateSync = require(script.Parent.StateSync)
local PlotService = require(script.Parent.PlotService)
local VacService = require(script.Parent.VacService)
local MarketService = require(script.Parent.MarketService)
local ShopService = require(script.Parent.ShopService)
local SlimeService = require(script.Parent.SlimeService)

Collision.init()
local refs = MapBuilder.build()

DataService.init()
StateSync.init()
PlotService.init()
VacService.init()
MarketService.init(refs.Intake, refs.ExchangeBoard, refs.ExchangePrompt)
ShopService.init(refs.WorkshopPosition)
SlimeService.init(refs.Spawners)

refs.WorkshopPrompt.Triggered:Connect(function(player)
	Remotes.event("OpenShop"):FireClient(player, "Vac")
end)

local function onPlayerAdded(player: Player)
	PlotService.hookPlayer(player)
	VacService.addPlayer(player)
	local data = DataService.load(player)
	if not data or not player.Parent then
		return
	end
	PlotService.claim(player)
	VacService.refreshJetpack(player)
	StateSync.mark(player)
end

local function onPlayerRemoving(player: Player)
	VacService.removePlayer(player)
	ShopService.removePlayer(player)
	-- snapshot + clear the corral first so nothing can be stolen mid-save
	PlotService.vacate(player)
	DataService.release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
