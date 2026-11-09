--!strict
-- Pushes a player's state snapshot to their client, batched to once per frame.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local StateRemote = Remotes.event("State")

local StateSync = {}
local dirty: { [Player]: boolean } = {}

function StateSync.mark(player: Player)
	dirty[player] = true
end

local function snapshot(player: Player): { [string]: any }?
	local d = DataService.get(player)
	if not d then
		return nil
	end
	local slots = Config.VacUpgrades.Slots.Values[d.Vac.Slots]
	local tank = {}
	for i = 1, slots do
		local s = d.Tank[i]
		tank[i] = { Id = s and s.Id, Count = s and s.Count or 0 }
	end
	return {
		Coins = d.Coins,
		Bank = d.Bank,
		Security = d.Security,
		Capacity = d.Capacity,
		PlotUpgrades = d.PlotUpgrades,
		Vac = d.Vac,
		Tank = tank,
		Selected = d.Selected,
		TankCap = Config.VacUpgrades.Tank.Values[d.Vac.Tank],
		Jetpack = Config.VacUpgrades.Jetpack.Values[d.Vac.Jetpack],
		PlotIndex = player:GetAttribute("PlotIndex") or 0,
	}
end

local function ensureLeaderstats(player: Player): IntValue?
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = ls
		ls.Parent = player
	end
	return (ls :: Instance):FindFirstChild("Coins") :: IntValue?
end

function StateSync.init()
	RunService.Heartbeat:Connect(function()
		if next(dirty) == nil then
			return
		end
		local batch = dirty
		dirty = {}
		for player in batch do
			if player.Parent ~= Players then
				continue
			end
			local snap = snapshot(player)
			if snap then
				StateRemote:FireClient(player, snap)
				local coins = ensureLeaderstats(player)
				if coins then
					coins.Value = snap.Coins
				end
			end
		end
	end)
end

return StateSync
