--!strict
-- Upgrade purchases. Client sends (category, key); server checks distance to
-- the right terminal, price, ordering, and max level. Nothing else is trusted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StateSync = require(script.Parent.StateSync)
local VacService = require(script.Parent.VacService)

local FxRemote = Remotes.event("Fx")

local ShopService = {}
local lastCall: { [Player]: number } = {}
local workshopPos = Vector3.zero

local function rootPos(player: Player): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function charge(d: DataService.Data, price: number): (boolean, string?)
	if d.Coins < price then
		return false, `Need {price - d.Coins} more coins`
	end
	d.Coins -= price
	return true, nil
end

local function buyRanch(player: Player, d: DataService.Data, key: string): (boolean, string)
	local plot = PlotService.plotOf(player)
	if not plot then
		return false, "You don't have a ranch"
	end
	local pos = rootPos(player)
	if not pos or (pos - plot.CFrame.Position).Magnitude > 60 then
		return false, "Use the Ranch Tech console at your ranch"
	end

	if key == "Security" then
		local nextTier = d.Security + 1
		local tier = Config.SecurityTiers[nextTier]
		if not tier then
			return false, "Security is maxed"
		end
		local ok, err = charge(d, tier.Price)
		if not ok then
			return false, err :: string
		end
		d.Security = nextTier
		PlotService.applyState(plot)
		FxRemote:FireAllClients("upgrade", plot.Index)
		return true, `{tier.Name} installed!`
	elseif key == "Capacity" then
		local nextLevel = d.Capacity + 1
		local price = Config.Capacity.Prices[nextLevel]
		if not price then
			return false, "Capacity is maxed"
		end
		local ok, err = charge(d, price)
		if not ok then
			return false, err :: string
		end
		d.Capacity = nextLevel
		return true, `Corral now holds {Config.Capacity.Levels[nextLevel]} slimes`
	else
		local def = Config.PlotUpgrades[key]
		if not def then
			return false, "Unknown upgrade"
		end
		if d.PlotUpgrades[key] then
			return false, "Already owned"
		end
		local ok, err = charge(d, def.Price)
		if not ok then
			return false, err :: string
		end
		d.PlotUpgrades[key] = true
		PlotService.applyState(plot)
		FxRemote:FireAllClients("upgrade", plot.Index)
		return true, `{def.Name} installed!`
	end
end

local function buyVac(player: Player, d: DataService.Data, key: string): (boolean, string)
	local def = (Config.VacUpgrades :: any)[key]
	if not def then
		return false, "Unknown upgrade"
	end
	local pos = rootPos(player)
	if not pos or (pos - workshopPos).Magnitude > 25 then
		return false, "Visit the Vac Workshop"
	end
	local level = (d.Vac :: any)[key] :: number
	local nextLevel = level + 1
	local price = def.Prices[nextLevel]
	if not price then
		return false, `{def.Name} is maxed`
	end
	local ok, err = charge(d, price)
	if not ok then
		return false, err :: string
	end
	(d.Vac :: any)[key] = nextLevel
	if key == "Slots" then
		for i = #d.Tank + 1, Config.VacUpgrades.Slots.Values[nextLevel] do
			d.Tank[i] = { Count = 0 }
		end
	elseif key == "Jetpack" then
		VacService.refreshJetpack(player)
	end
	return true, `{def.Name} upgraded!`
end

function ShopService.init(workshopPosition: Vector3)
	workshopPos = workshopPosition
	Remotes.func("Purchase").OnServerInvoke = function(player: Player, category: any, key: any)
		local t = os.clock()
		if t - (lastCall[player] or 0) < 0.25 then
			return false, "Slow down"
		end
		lastCall[player] = t
		if typeof(category) ~= "string" or typeof(key) ~= "string" then
			return false, "Bad request"
		end
		local d = DataService.get(player)
		if not d then
			return false, "Data not loaded"
		end
		local ok: boolean, msg: string
		if category == "Ranch" then
			ok, msg = buyRanch(player, d, key)
		elseif category == "Vac" then
			ok, msg = buyVac(player, d, key)
		else
			return false, "Bad request"
		end
		if ok then
			StateSync.mark(player)
		end
		return ok, msg
	end
end

function ShopService.removePlayer(player: Player)
	lastCall[player] = nil
end

return ShopService
