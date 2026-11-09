--!strict
-- Session-locked DataStore wrapper.
--  * UpdateAsync everywhere (no blind SetAsync overwrites)
--  * session lock so a fast server-hop can't load stale data and dupe
--  * every loaded field is sanitised/clamped; nothing from the store is trusted
--  * retries with backoff; Studio without API access runs in offline mode

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)

export type TankSlot = { Id: string?, Count: number }
export type Data = {
	Version: number,
	Coins: number,
	Bank: { [string]: number },
	Security: number,
	Capacity: number,
	PlotUpgrades: { [string]: boolean },
	Vac: { Tank: number, Slots: number, Power: number, Jetpack: number },
	Tank: { TankSlot },
	Selected: number,
	Slimes: { string },
}

local DataService = {}

local profiles: { [Player]: { Data: Data, CanSave: boolean } } = {}
local beforeSave: { (Player, Data) -> () } = {}
local offline = false

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		offline = true
		warn("[Data] DataStore unavailable, running offline:", result)
	end
end

local function default(): Data
	return {
		Version = 1,
		Coins = Config.Data.StartingCoins,
		Bank = {},
		Security = 1,
		Capacity = 1,
		PlotUpgrades = { Collector = false, MusicBox = false, Feeder = false },
		Vac = { Tank = 1, Slots = 1, Power = 1, Jetpack = 1 },
		Tank = {},
		Selected = 1,
		Slimes = {},
	}
end

local function int(v: any, lo: number, hi: number, fallback: number): number
	if typeof(v) ~= "number" or v ~= v then
		return fallback
	end
	return math.clamp(math.floor(v), lo, hi)
end

-- Turn whatever came out of the store into a valid Data table.
local function sanitize(raw: any): Data
	local d = default()
	if typeof(raw) ~= "table" then
		return d
	end
	d.Coins = int(raw.Coins, 0, 1e12, d.Coins)
	d.Security = int(raw.Security, 1, #Config.SecurityTiers, 1)
	d.Capacity = int(raw.Capacity, 1, #Config.Capacity.Levels, 1)

	if typeof(raw.PlotUpgrades) == "table" then
		for key in Config.PlotUpgrades do
			d.PlotUpgrades[key] = raw.PlotUpgrades[key] == true
		end
	end
	if typeof(raw.Vac) == "table" then
		for key, def in Config.VacUpgrades do
			(d.Vac :: any)[key] = int(raw.Vac[key], 1, #def.Values, 1)
		end
	end
	if typeof(raw.Bank) == "table" then
		for t in Config.Slimes do
			local n = int(raw.Bank[t], 0, 1e7, 0)
			if n > 0 then
				d.Bank[t] = n
			end
		end
	end

	local slots = Config.VacUpgrades.Slots.Values[d.Vac.Slots]
	local cap = Config.VacUpgrades.Tank.Values[d.Vac.Tank]
	if typeof(raw.Tank) == "table" then
		for i = 1, slots do
			local s = raw.Tank[i]
			if typeof(s) == "table" and ItemIds.parse(s.Id) then
				local n = int(s.Count, 0, cap, 0)
				d.Tank[i] = if n > 0 then { Id = s.Id, Count = n } else { Count = 0 }
			else
				d.Tank[i] = { Count = 0 }
			end
		end
	end
	for i = #d.Tank + 1, slots do
		d.Tank[i] = { Count = 0 }
	end
	d.Selected = int(raw.Selected, 1, slots, 1)

	local maxSlimes = Config.Capacity.Levels[d.Capacity]
	if typeof(raw.Slimes) == "table" then
		for _, id in raw.Slimes do
			if #d.Slimes >= maxSlimes then
				break
			end
			local p = ItemIds.parse(id)
			if p and p.Kind == "slime" then
				table.insert(d.Slimes, id)
			end
		end
	end
	return d
end

local function key(player: Player): string
	return `p_{player.UserId}`
end

local function isStudioNoAccess(err: any): boolean
	local s = tostring(err)
	return RunService:IsStudio()
		and (string.find(s, "StudioAccessToApisNotAllowed") ~= nil or string.find(s, "403") ~= nil)
end

-- Returns data, canSave. Returns nil if the player should be kicked.
local function loadWithLock(player: Player): (Data?, boolean)
	if offline or not store then
		return default(), false
	end
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	for attempt = 1, Config.Data.LoadAttempts do
		local lockedElsewhere = false
		local result: Data? = nil
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(player), function(old: any)
				local lock = if typeof(old) == "table" then old.Lock else nil
				if typeof(lock) == "table" and lock.Job ~= jobId
					and typeof(lock.Time) == "number"
					and os.time() - lock.Time < Config.Data.SessionLockTimeout then
					lockedElsewhere = true
					return nil -- cancel write
				end
				local data = sanitize(old)
				result = data
				local out = table.clone(data) :: any
				out.Lock = { Job = jobId, Time = os.time() }
				return out
			end)
		end)
		if ok and result then
			return result, true
		end
		if not ok and isStudioNoAccess(err) then
			warn("[Data] Studio has no API access. Enable it in Game Settings > Security to test saving.")
			offline = true
			return default(), false
		end
		if not ok then
			warn(`[Data] load attempt {attempt} failed for {player.Name}: {err}`)
		end
		if not player.Parent then
			return nil, false
		end
		-- Another server still holds the lock (usually it's mid-save after a hop).
		task.wait(if lockedElsewhere then 4 else 2 ^ attempt)
	end
	return nil, false
end

local function writeData(player: Player, data: Data, release: boolean): boolean
	if not store then
		return false
	end
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(player), function(old: any)
				local lock = if typeof(old) == "table" then old.Lock else nil
				-- Never clobber data another server has since taken over.
				if typeof(lock) == "table" and lock.Job ~= jobId then
					return nil
				end
				local out = table.clone(data) :: any
				out.Lock = if release then nil else { Job = jobId, Time = os.time() }
				return out
			end)
		end)
		if ok then
			return true
		end
		warn(`[Data] save attempt {attempt} failed for {player.Name}: {err}`)
		task.wait(2 ^ attempt)
	end
	return false
end

function DataService.onBeforeSave(fn: (Player, Data) -> ())
	table.insert(beforeSave, fn)
end

function DataService.get(player: Player): Data?
	local p = profiles[player]
	return if p then p.Data else nil
end

function DataService.load(player: Player): Data?
	local data, canSave = loadWithLock(player)
	if not data then
		player:Kick("Couldn't load your ranch data. Rejoin in a minute - nothing was lost.")
		return nil
	end
	if not player.Parent then
		-- left while loading; release the lock we just took
		if canSave then
			writeData(player, data, true)
		end
		return nil
	end
	profiles[player] = { Data = data, CanSave = canSave }
	return data
end

function DataService.save(player: Player, release: boolean)
	local p = profiles[player]
	if not p then
		return
	end
	for _, fn in beforeSave do
		local ok, err = pcall(fn, player, p.Data)
		if not ok then
			warn("[Data] beforeSave hook errored:", err)
		end
	end
	if p.CanSave then
		writeData(player, p.Data, release)
	end
end

function DataService.release(player: Player)
	DataService.save(player, true)
	profiles[player] = nil
end

function DataService.init()
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player in profiles do
				task.spawn(DataService.save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.release(player)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.2)
		end
	end)
	-- Release on leave is driven by Main (it has to snapshot the corral first).
end

return DataService
