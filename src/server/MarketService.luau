--!strict
-- Gem Exchange. Prices drift over time and drop as people dump the same gem
-- type (saturation), then recover. Encourages farming several slime types.
--
-- Two ways to sell:
--   * shoot gems into the glowing intake funnel (credited to whoever shot them)
--   * "Sell All Gems" prompt: sells your Gem Bank + any gems in your vac tank

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local StateSync = require(script.Parent.StateSync)

local MK = Config.Market
local FxRemote = Remotes.event("Fx")
local NotifyRemote = Remotes.event("Notify")

local MarketService = {}

local mult: { [string]: number } = {}
local target: { [string]: number } = {}
local lastPrice: { [string]: number } = {}
local priceFolder: Folder
local rows: { [string]: { Price: TextLabel, Trend: TextLabel } } = {}

local function priceOf(t: string): number
	return math.max(1, math.floor(Config.Slimes[t].GemValue * mult[t] + 0.5))
end

local function publish()
	for _, t in Config.SlimeOrder do
		local p = priceOf(t)
		local prev = lastPrice[t] or p
		if p ~= prev or priceFolder:GetAttribute(t) == nil then
			priceFolder:SetAttribute(t, p)
			local row = rows[t]
			if row then
				row.Price.Text = tostring(p)
				if p > prev then
					row.Trend.Text = "▲"
					row.Trend.TextColor3 = Color3.fromRGB(120, 255, 150)
				elseif p < prev then
					row.Trend.Text = "▼"
					row.Trend.TextColor3 = Color3.fromRGB(255, 120, 120)
				end
			end
		end
		lastPrice[t] = p
	end
end

local function buildBoard(board: BasePart)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front -- board front faces the path (see MapBuilder)
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 32
	g.LightInfluence = 0
	g.Brightness = 1.4
	g.MaxDistance = 160
	g.Parent = board

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.2)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 210, 110)
	title.Text = "GEM EXCHANGE"
	title.Parent = g

	local n = #Config.SlimeOrder
	for i, t in Config.SlimeOrder do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(0.9, 0.75 / n)
		row.Position = UDim2.fromScale(0.05, 0.22 + (i - 1) * 0.75 / n)
		row.Parent = g

		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromScale(0.07, 0.75)
		dot.Position = UDim2.fromScale(0, 0.125)
		dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
		dot.BackgroundColor3 = Config.Slimes[t].Color
		dot.Rotation = 45
		dot.Parent = row

		local name = Instance.new("TextLabel")
		name.Size = UDim2.fromScale(0.5, 1)
		name.Position = UDim2.fromScale(0.12, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Text = `{Config.Slimes[t].Display} Gem`
		name.Parent = row

		local price = Instance.new("TextLabel")
		price.Size = UDim2.fromScale(0.25, 1)
		price.Position = UDim2.fromScale(0.62, 0)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.FredokaOne
		price.TextScaled = true
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.TextColor3 = Color3.fromRGB(255, 225, 120)
		price.Text = "-"
		price.Parent = row

		local trend = Instance.new("TextLabel")
		trend.Size = UDim2.fromScale(0.1, 1)
		trend.Position = UDim2.fromScale(0.9, 0)
		trend.BackgroundTransparency = 1
		trend.Font = Enum.Font.FredokaOne
		trend.TextScaled = true
		trend.TextColor3 = Color3.new(1, 1, 1)
		trend.Text = ""
		trend.Parent = row

		rows[t] = { Price = price, Trend = trend }
	end
end

-- Returns coins earned.
function MarketService.sell(player: Player, gemType: string, count: number): number
	local d = DataService.get(player)
	if not d or count <= 0 or not Config.Slimes[gemType] then
		return 0
	end
	local total = 0
	for _ = 1, count do
		total += priceOf(gemType)
		mult[gemType] = math.max(MK.MinMultiplier, mult[gemType] - MK.SaturationPerGem)
	end
	d.Coins += total
	StateSync.mark(player)
	publish()
	return total
end

local function sellAll(player: Player)
	local d = DataService.get(player)
	if not d then
		return
	end
	local earned, sold = 0, 0
	for t, n in d.Bank do
		earned += MarketService.sell(player, t, n)
		sold += n
	end
	d.Bank = {}
	for i, s in d.Tank do
		local parsed = s.Id and ItemIds.parse(s.Id)
		if parsed and parsed.Kind == "gem" and s.Count > 0 then
			earned += MarketService.sell(player, parsed.A, s.Count)
			sold += s.Count
			d.Tank[i] = { Count = 0 }
		end
	end
	StateSync.mark(player)
	if sold == 0 then
		NotifyRemote:FireClient(player, "No gems to sell. Shoot gems into the funnel or get a Gem Collector.", "info")
	else
		NotifyRemote:FireClient(player, `Sold {sold} gems for {earned} coins`, "coins")
		FxRemote:FireClient(player, "coins", earned)
	end
end

function MarketService.init(intake: BasePart, board: BasePart, prompt: ProximityPrompt)
	priceFolder = Instance.new("Folder")
	priceFolder.Name = "MarketPrices"
	priceFolder.Parent = ReplicatedStorage

	for _, t in Config.SlimeOrder do
		mult[t] = 1
		target[t] = 1
	end
	buildBoard(board)
	publish()

	intake.Touched:Connect(function(hit)
		if hit:GetAttribute("Kind") ~= "gem" or hit:GetAttribute("Sold") then
			return
		end
		hit:SetAttribute("Sold", true)
		local parsed = ItemIds.parse(hit:GetAttribute("Id"))
		local shooter = Players:GetPlayerByUserId((hit:GetAttribute("ShooterId") or 0) :: number)
		local pos = hit.Position
		hit:Destroy()
		if parsed and shooter then
			local earned = MarketService.sell(shooter, parsed.A, 1)
			FxRemote:FireAllClients("sell", pos, earned, shooter.UserId)
		end
	end)

	prompt.Triggered:Connect(sellAll)

	task.spawn(function()
		local sinceReroll = 0
		while true do
			task.wait(MK.DriftInterval)
			sinceReroll += MK.DriftInterval
			if sinceReroll >= MK.TargetRerollInterval then
				sinceReroll = 0
				for _, t in Config.SlimeOrder do
					target[t] = MK.TargetRange[1] + math.random() * (MK.TargetRange[2] - MK.TargetRange[1])
				end
			end
			for _, t in Config.SlimeOrder do
				mult[t] += (target[t] - mult[t]) * MK.RecoverRate
			end
			publish()
		end
	end)
end

return MarketService
