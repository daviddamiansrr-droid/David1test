--!strict
-- Upgrade panel for the Ranch Tech console ("Ranch") and Vac Workshop ("Vac").
-- Purely a view: every purchase is validated server-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local PANEL = Color3.fromRGB(22, 28, 44)
local ACCENT = Config.Fence.Color

local ShopUI = {}

local gui: ScreenGui
local window: Frame
local scale: UIScale
local title: TextLabel
local list: ScrollingFrame
local category: string? = nil
local openedAt: Vector3? = nil
local busy = false

type Row = { Key: string, Name: string, Desc: string, Level: number, MaxLevel: number, Price: number?, Detail: string }

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function rowsFor(cat: string, snap: { [string]: any }): { Row }
	local rows: { Row } = {}
	if cat == "Ranch" then
		local cur = snap.Security
		local nextTier = Config.SecurityTiers[cur + 1]
		table.insert(rows, {
			Key = "Security",
			Name = if nextTier then nextTier.Name else Config.SecurityTiers[cur].Name,
			Desc = if nextTier then nextTier.Desc else "Your ranch is a fortress.",
			Level = cur,
			MaxLevel = #Config.SecurityTiers,
			Price = nextTier and nextTier.Price,
			Detail = if nextTier
				then `Walls {Config.SecurityTiers[cur].WallHeight} -> {nextTier.WallHeight}  ·  Lock {nextTier.LockSeconds}s`
				else "MAX",
		})
		local capNext = Config.Capacity.Levels[snap.Capacity + 1]
		table.insert(rows, {
			Key = "Capacity",
			Name = "Corral Expansion",
			Desc = "More slimes saved and producing in your corral.",
			Level = snap.Capacity,
			MaxLevel = #Config.Capacity.Levels,
			Price = Config.Capacity.Prices[snap.Capacity + 1],
			Detail = if capNext then `{Config.Capacity.Levels[snap.Capacity]} -> {capNext} slimes` else "MAX",
		})
		for _, key in { "Collector", "MusicBox", "Feeder" } do
			local def = Config.PlotUpgrades[key]
			local owned = snap.PlotUpgrades[key] == true
			table.insert(rows, {
				Key = key,
				Name = def.Name,
				Desc = def.Desc,
				Level = if owned then 1 else 0,
				MaxLevel = 1,
				Price = if owned then nil else def.Price,
				Detail = if owned then "Installed" else "",
			})
		end
	else
		for _, key in { "Tank", "Slots", "Power", "Jetpack" } do
			local def = (Config.VacUpgrades :: any)[key]
			local lv = snap.Vac[key] :: number
			local cur, nxt = def.Values[lv], def.Values[lv + 1]
			local unit = if key == "Tank" then " per slot" elseif key == "Slots" then " slots" elseif key == "Power" then " stud range" else ""
			table.insert(rows, {
				Key = key,
				Name = def.Name,
				Desc = def.Desc,
				Level = lv,
				MaxLevel = #def.Values,
				Price = def.Prices[lv + 1],
				Detail = if nxt then `{if key == "Jetpack" and cur == 0 then "none" else tostring(cur)} -> {nxt}{unit}` else "MAX",
			})
		end
	end
	return rows
end

local function render()
	local snap = ClientState.Data
	if not category or not snap then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, row in rowsFor(category, snap) do
		local f = new("Frame", { Size = UDim2.new(1, -8, 0, 92), BackgroundColor3 = Color3.fromRGB(34, 42, 62), LayoutOrder = i }, list)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, f)
		new("TextLabel", { Size = UDim2.new(0.62, 0, 0, 28), Position = UDim2.fromOffset(14, 8), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), Text = row.Name }, f)
		new("TextLabel", { Size = UDim2.new(0.62, 0, 0, 34), Position = UDim2.fromOffset(14, 36), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextWrapped = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(190, 200, 220), Text = row.Desc }, f)
		new("TextLabel", { Size = UDim2.new(0.62, 0, 0, 16), Position = UDim2.fromOffset(14, 70), BackgroundTransparency = 1, Font = FONT, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = ACCENT, Text = row.Detail }, f)

		-- level pips
		local pips = new("Frame", { Size = UDim2.fromOffset(120, 10), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), BackgroundTransparency = 1 }, f)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4) }, pips)
		for k = 1, row.MaxLevel do
			local pip = new("Frame", { Size = UDim2.fromOffset(16, 10), BackgroundColor3 = if k <= row.Level then ACCENT else Color3.fromRGB(70, 80, 105), BorderSizePixel = 0 }, pips)
			new("UICorner", { CornerRadius = UDim.new(0, 4) }, pip)
		end

		local affordable = row.Price ~= nil and snap.Coins >= row.Price
		local b = new("TextButton", {
			Size = UDim2.fromOffset(130, 42),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -14, 1, -10),
			BackgroundColor3 = if row.Price == nil then Color3.fromRGB(70, 80, 105) elseif affordable then Color3.fromRGB(110, 220, 140) else Color3.fromRGB(150, 90, 90),
			Font = FONT,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = row.Price ~= nil,
			Text = if row.Price == nil then (if row.MaxLevel == 1 then "OWNED" else "MAX") elseif row.Price == 0 then "FREE" else `{row.Price}`,
		}, f)
		new("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, b)
		if row.Price ~= nil then
			b.Activated:Connect(function()
				if busy then
					return
				end
				busy = true
				local ok, msg = Remotes.func("Purchase"):InvokeServer(category, row.Key)
				busy = false
				Hud.toast(msg or "", if ok then "good" else "error")
				Sounds.play(if ok then "Upgrade" else "Full", 0.6, if ok then 1 else 0.7)
				if ok then
					local s = b:FindFirstChildOfClass("UIScale") or new("UIScale", {}, b)
					s.Scale = 1.2
					TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				end
			end)
		end
	end
end

function ShopUI.close()
	if not category then
		return
	end
	category = nil
	local tw = TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 0.8 })
	tw:Play()
	tw.Completed:Connect(function()
		if not category then
			window.Visible = false
		end
	end)
end

function ShopUI.open(cat: string)
	category = cat
	title.Text = if cat == "Ranch" then "RANCH TECH" else "VAC WORKSHOP"
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	openedAt = root and root.Position
	window.Visible = true
	scale.Scale = 0.7
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Sounds.play("Button", 0.4, 1.1)
	render()
end

function ShopUI.init()
	gui = new("ScreenGui", { Name = "RanchShop", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5 }, player:WaitForChild("PlayerGui"))
	window = new("Frame", { Size = UDim2.new(0.9, 0, 0.78, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), BackgroundColor3 = PANEL, Visible = false }, gui)
	new("UISizeConstraint", { MaxSize = Vector2.new(560, 520) }, window)
	new("UICorner", { CornerRadius = UDim.new(0, 20) }, window)
	new("UIStroke", { Color = ACCENT, Thickness = 3, Transparency = 0.3 }, window)
	scale = new("UIScale", {}, window)
	title = new("TextLabel", { Size = UDim2.new(1, -80, 0, 44), Position = UDim2.fromOffset(20, 10), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = ACCENT, Text = "" }, window)
	local close = new("TextButton", { Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), BackgroundColor3 = Color3.fromRGB(60, 70, 95), Font = FONT, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "X" }, window)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, close)
	close.Activated:Connect(ShopUI.close)

	list = new("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -70), Position = UDim2.fromOffset(12, 62), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, window)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	Remotes.event("OpenShop").OnClientEvent:Connect(function(cat)
		if cat == "Ranch" or cat == "Vac" then
			ShopUI.open(cat)
		end
	end)
	ClientState.Changed:Connect(render)

	-- walking away closes it
	task.spawn(function()
		while true do
			task.wait(0.5)
			if category and openedAt then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not root or (root.Position - openedAt).Magnitude > 22 then
					ShopUI.close()
				end
			end
		end
	end)
end

return ShopUI
