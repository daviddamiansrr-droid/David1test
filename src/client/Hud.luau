--!strict
-- Main HUD, laid out after the reference screenshot:
--   top centre   : star level badge, "Ranch Lv. X", XP bar in a goo frame, slime face
--   left         : Shop (with ! badge), Index, Invite
--   right        : Hoverboard, Jetpack (+ fuel), Home (fast travel)
--   bottom left  : Slime Coins + coins/sec (moves top-left on touch so it
--                  doesn't sit under the thumbstick)
--   bottom centre: goo hotbar; numbered navy slots, "xN" counts, "+" when empty.
--                  Starts at 2 slots; each upgrade pops a new slot in.
--   + toasts, reticle, mobile VAC/SHOOT buttons
--
-- Everything is drawn in code. Icons are emoji placeholders until ids are set
-- in Config.UI.Icons.
--
-- Data: slots/coins come from the server snapshot (ClientState). Level, XP and
-- coins/sec are read from player attributes RanchLevel, RanchXP, RanchXPMax,
-- CoinsPerSecond (and Coins overrides the snapshot if your game sets it), so
-- any existing system can drive them by setting attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)
local ClientState = require(script.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local INK = Color3.fromRGB(38, 18, 72) -- dark outline used on all text
local CYAN = Color3.fromRGB(110, 230, 255)

local Hud = {}

----------------------------------------------------------------------
-- signals
----------------------------------------------------------------------
local function signal(): (BindableEvent, RBXScriptSignal)
	local b = Instance.new("BindableEvent")
	return b, b.Event
end
local vacBegan, vacEnded, shootPressed, slotPressed
local shopPressed, indexPressed, hoverPressed, jetPressed, homePressed, settingsPressed
vacBegan, Hud.MobileVacBegan = signal()
vacEnded, Hud.MobileVacEnded = signal()
shootPressed, Hud.MobileShoot = signal()
slotPressed, Hud.SlotPressed = signal()
shopPressed, Hud.ShopPressed = signal()
indexPressed, Hud.IndexPressed = signal()
hoverPressed, Hud.HoverboardPressed = signal()
jetPressed, Hud.JetpackPressed = signal()
homePressed, Hud.HomePressed = signal()
settingsPressed, Hud.SettingsPressed = signal()

----------------------------------------------------------------------
-- tiny UI kit
----------------------------------------------------------------------
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

local function corner(parent: Instance, r: number?)
	return new("UICorner", { CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0) }, parent)
end

local function gradient(parent: Instance, top: Color3, bottom: Color3)
	return new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, parent)
end

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function pop(scale: UIScale, amount: number?)
	scale.Scale = amount or 1.2
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- chunky white text with a dark outline, like the reference
local function label(parent: Instance, props: { [string]: any }, strokeColor: Color3?, strokeThickness: number?): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
	}, parent)
	for k, v in props do
		(l :: any)[k] = v
	end
	new("UIStroke", { Color = strokeColor or INK, Thickness = strokeThickness or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	return l
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- seeded random so the goo blobs look the same every session
local blobRng = Random.new(42)

-- purple goo panel: gradient body, lighter blobs, glossy streak, drips
local function goo(frame: GuiObject, opts: { Radius: number?, Drips: number?, Blobs: number?, Light: Color3?, Body: Color3?, Dark: Color3? })
	local light = opts.Light or Color3.fromRGB(186, 98, 255)
	local body = opts.Body or Color3.fromRGB(150, 62, 232)
	local dark = opts.Dark or Color3.fromRGB(112, 38, 198)
	frame.BackgroundColor3 = body
	frame.BackgroundTransparency = 0
	corner(frame, opts.Radius)
	gradient(frame, light, dark)
	new("UIStroke", { Color = Color3.fromRGB(232, 168, 255), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	if Config.UI.GooPanel ~= "" then
		new("ImageLabel", {
			Name = "GooArt",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = Config.UI.GooPanel,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(64, 64, 192, 192),
			ZIndex = 0,
		}, frame)
		return
	end
	for _ = 1, opts.Blobs or 10 do
		local s = blobRng:NextInteger(10, 30)
		local b = new("Frame", {
			Name = "Blob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(s, math.floor(s * blobRng:NextNumber(0.6, 1))),
			Position = UDim2.fromScale(blobRng:NextNumber(0.08, 0.92), blobRng:NextNumber(0.25, 0.8)),
			BackgroundColor3 = Color3.fromRGB(205, 130, 255),
			BackgroundTransparency = blobRng:NextNumber(0.45, 0.7),
			BorderSizePixel = 0,
			ZIndex = 0,
		}, frame)
		corner(b)
	end
	local gloss = new("Frame", { Name = "Gloss", Size = UDim2.new(1, -36, 0, 5), Position = UDim2.fromOffset(18, 5), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 0 }, frame)
	corner(gloss)
	for _ = 1, opts.Drips or 0 do
		local w = blobRng:NextInteger(9, 15)
		local drip = new("Frame", {
			Name = "Drip",
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(w, blobRng:NextInteger(12, 24)),
			Position = UDim2.new(blobRng:NextNumber(0.12, 0.88), 0, 1, -8),
			BackgroundColor3 = dark,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, frame)
		corner(drip)
	end
end

local function icon(parent: Instance, key: string, emoji: string, size: UDim2, pos: UDim2): GuiObject
	local id = (Config.UI.Icons :: any)[key]
	if id and id ~= "" then
		return new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = id, Size = size, Position = pos, AnchorPoint = Vector2.new(0.5, 0.5), ScaleType = Enum.ScaleType.Fit }, parent)
	end
	return new("TextLabel", { Name = "Icon", BackgroundTransparency = 1, Text = emoji, TextScaled = true, Font = Enum.Font.GothamBold, Size = size, Position = pos, AnchorPoint = Vector2.new(0.5, 0.5) }, parent)
end

-- the big square menu buttons
local function menuButton(parent: Instance, order: number, key: string, emoji: string, text: string?, top: Color3, bottom: Color3, goo_: boolean?): (TextButton, Frame)
	local holder = new("Frame", { Name = key, Size = UDim2.fromOffset(112, 112), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	-- dark rim + drop shadow behind the white border
	local shadow = new("Frame", { Size = UDim2.new(1, 6, 1, 6), Position = UDim2.fromOffset(-3, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.1 }, holder)
	corner(shadow, 26)
	local b = new("TextButton", { Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false, BackgroundColor3 = bottom }, holder)
	if goo_ then
		goo(b, { Radius = 24, Blobs = 6, Light = top, Body = bottom:Lerp(top, 0.5), Dark = bottom })
	else
		corner(b, 24)
		gradient(b, top, bottom)
	end
	local border = b:FindFirstChildOfClass("UIStroke") or new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	border.Color = Color3.new(1, 1, 1)
	border.Thickness = 4
	-- shine on the top half
	local shine = new("Frame", { Size = UDim2.new(1, -16, 0.38, 0), Position = UDim2.fromOffset(8, 6), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, BorderSizePixel = 0 }, b)
	corner(shine, 18)
	local scale = new("UIScale", {}, holder)
	if text then
		icon(b, key, emoji, UDim2.fromScale(0.62, 0.55), UDim2.fromScale(0.5, 0.38))
		label(b, { Size = UDim2.new(1, -10, 0.3, 0), Position = UDim2.new(0, 5, 0.66, 0), Text = text })
	else
		icon(b, key, emoji, UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.5, 0.5))
	end
	b.MouseButton1Down:Connect(function()
		scale.Scale = 0.9
	end)
	b.Activated:Connect(function()
		pop(scale, 1.08)
		Sounds.play("Button")
	end)
	b.MouseLeave:Connect(function()
		if scale.Scale < 1 then
			tween(scale, 0.15, { Scale = 1 })
		end
	end)
	return b, holder
end

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------
local gui: ScreenGui
local hotbar: Frame
type Slot = { Root: Frame, Scale: UIScale, Stroke: UIStroke, Badge: Frame, Icon: Frame, Count: TextLabel, Plus: TextLabel }
local slots: { Slot } = {}
local shownSlots = 0
local coinLabel: TextLabel
local coinScale: UIScale
local incomeLabel: TextLabel
local levelTitle: TextLabel
local levelNumber: TextLabel
local xpFill: Frame
local xpText: TextLabel
local lockChip: TextLabel
local shopBadge: Frame
local toastHolder: Frame
local fuelFrame: Frame
local fuelFill: Frame
local reticle: Frame
local reticleScale: UIScale
local mobileButtons: Frame
local shownCoins = -1
local equipped = false

----------------------------------------------------------------------
-- item icons: rounded cubes with faces, like the reference hotbar
----------------------------------------------------------------------
local function paintIcon(iconFrame: Frame, id: string?)
	for _, c in iconFrame:GetChildren() do
		c:Destroy()
	end
	if not id then
		iconFrame.Visible = false
		return
	end
	iconFrame.Visible = true
	local parsed = ItemIds.parse(id)
	local a, b = ItemIds.colors(id)
	iconFrame.BackgroundColor3 = a
	iconFrame.Rotation = 0
	if parsed and parsed.Kind == "gem" then
		iconFrame.Rotation = 45
		corner(iconFrame, 8)
		new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.3, Thickness = 2.5 }, iconFrame)
		return
	elseif parsed and parsed.Kind == "food" then
		corner(iconFrame)
		new("UIStroke", { Color = INK, Thickness = 2.5 }, iconFrame)
		return
	end
	corner(iconFrame, 12)
	new("UIStroke", { Color = INK, Thickness = 2.5 }, iconFrame)
	gradient(iconFrame, a:Lerp(Color3.new(1, 1, 1), 0.3), if b then b else a:Lerp(Color3.new(0, 0, 0), 0.15))
	local hl = new("Frame", { Size = UDim2.fromScale(0.3, 0.14), Position = UDim2.fromScale(0.14, 0.1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, iconFrame)
	corner(hl)
	for _, x in { 0.34, 0.66 } do
		local eye = new("Frame", { Size = UDim2.fromScale(0.13, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), BackgroundColor3 = INK, BorderSizePixel = 0 }, iconFrame)
		corner(eye)
	end
	local mouth = new("Frame", { Size = UDim2.fromScale(0.16, 0.08), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.68), BackgroundColor3 = INK, BorderSizePixel = 0 }, iconFrame)
	corner(mouth)
end

----------------------------------------------------------------------
-- hotbar
----------------------------------------------------------------------
local function buildSlot(i: number): Slot
	local root = new("Frame", { Name = `Slot{i}`, Size = UDim2.fromOffset(84, 84), BackgroundColor3 = Color3.fromRGB(34, 30, 82), LayoutOrder = i, ZIndex = 2 }, hotbar)
	corner(root, 18)
	gradient(root, Color3.fromRGB(46, 42, 108), Color3.fromRGB(26, 22, 62))
	local stroke = new("UIStroke", { Color = Color3.fromRGB(22, 14, 50), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, root)
	local scale = new("UIScale", {}, root)
	local iconFrame = new("Frame", { Name = "Item", Size = UDim2.fromOffset(50, 50), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BorderSizePixel = 0, Visible = false, ZIndex = 3 }, root)
	local plus = label(root, { Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Text = "+", ZIndex = 3 }, INK, 2)
	local count = label(root, { Size = UDim2.fromOffset(52, 26), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -3, 1, -1), Text = "", TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	-- numbered badge sitting on the top edge
	local badge = new("Frame", { Name = "Badge", Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), BackgroundColor3 = Color3.fromRGB(32, 30, 76), ZIndex = 5 }, root)
	corner(badge)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
	label(badge, { Size = UDim2.fromScale(0.75, 0.75), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Text = tostring(i), ZIndex = 6 }, INK, 1.5)
	local button = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, root)
	button.Activated:Connect(function()
		slotPressed:Fire(i)
	end)
	local s: Slot = { Root = root, Scale = scale, Stroke = stroke, Badge = badge, Icon = iconFrame, Count = count, Plus = plus }
	slots[i] = s
	return s
end

local function sparkBurst(at: GuiObject)
	for k = 1, 10 do
		local ang = (k / 10) * math.pi * 2 + math.random() * 0.3
		local sz = math.random(6, 12)
		local p = new("Frame", {
			Size = UDim2.fromOffset(sz, sz),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = if k % 2 == 0 then CYAN else Color3.fromRGB(255, 230, 120),
			BorderSizePixel = 0,
			Rotation = 45,
			ZIndex = 9,
		}, at)
		local dist = math.random(60, 95)
		tween(p, 0.55, { Position = UDim2.new(0.5, math.cos(ang) * dist, 0.5, math.sin(ang) * dist), BackgroundTransparency = 1, Rotation = 225 }, Enum.EasingStyle.Quart)
		task.delay(0.6, p.Destroy, p)
	end
end

-- new slot appears: pops in from nothing, flashes, sparkles, "NEW SLOT!"
local function unlockAnimation(s: Slot)
	s.Scale.Scale = 0
	s.Stroke.Color = Color3.new(1, 1, 1)
	s.Stroke.Thickness = 8
	task.delay(0.08, function()
		tween(s.Scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(s.Stroke, 0.7, { Thickness = 3, Color = Color3.fromRGB(22, 14, 50) })
		sparkBurst(s.Root)
		Sounds.play("SlotUnlock")
	end)
	local tag = label(s.Root, { Size = UDim2.fromOffset(120, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -14), Text = "NEW SLOT!", TextColor3 = Color3.fromRGB(255, 230, 120), ZIndex = 9 })
	local tagScale = new("UIScale", { Scale = 0 }, tag)
	tween(tagScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.3, function()
		tween(tag, 0.4, { Position = UDim2.new(0.5, 0, 0, -40), TextTransparency = 1 })
		local st = tag:FindFirstChildOfClass("UIStroke")
		if st then
			tween(st, 0.4, { Transparency = 1 })
		end
		task.delay(0.45, tag.Destroy, tag)
	end)
end

local function refreshSlots(snap: { [string]: any }, prev: { [string]: any }?)
	local tank = snap.Tank :: { { Id: string?, Count: number } }
	local animateNew = prev ~= nil and shownSlots > 0
	for i = #slots + 1, #tank do
		local s = buildSlot(i)
		if animateNew and i > shownSlots then
			unlockAnimation(s)
		end
	end
	shownSlots = math.max(shownSlots, #tank)
	for i, s in slots do
		local data = tank[i]
		s.Root.Visible = data ~= nil
		if not data then
			continue
		end
		local prevSlot = prev and prev.Tank and prev.Tank[i]
		if not prevSlot or prevSlot.Id ~= data.Id or s.Icon.Visible == (data.Id == nil) then
			paintIcon(s.Icon, if data.Count > 0 then data.Id else nil)
		end
		s.Plus.Visible = data.Count <= 0
		s.Count.Text = if data.Count > 0 then `x{data.Count}` else ""
		s.Count.TextColor3 = if data.Count >= snap.TankCap then Color3.fromRGB(255, 220, 90) else Color3.new(1, 1, 1)
		local selected = snap.Selected == i
		if s.Stroke.Thickness < 5 then -- don't stomp the unlock flash
			s.Stroke.Color = if selected then CYAN else Color3.fromRGB(22, 14, 50)
			s.Stroke.Thickness = if selected then 4 else 3
		end
		s.Badge.BackgroundColor3 = if selected then Color3.fromRGB(60, 170, 255) else Color3.fromRGB(32, 30, 76)
		s.Root.Position = UDim2.fromOffset(0, if selected then -6 else 0)
	end
end

function Hud.bounceSlot(i: number)
	local s = slots[i]
	if s and s.Scale.Scale > 0.9 then
		pop(s.Scale, 1.15)
	end
end

function Hud.denySlot(i: number)
	local s = slots[i]
	if not s then
		return
	end
	local original = s.Root.Position
	s.Stroke.Color = Color3.fromRGB(255, 90, 90)
	for k = 1, 4 do
		task.delay(k * 0.04, function()
			s.Root.Position = original + UDim2.fromOffset(if k % 2 == 0 then 4 else -4, 0)
		end)
	end
	task.delay(0.2, function()
		s.Root.Position = original
		local snap = ClientState.Data
		if snap then
			refreshSlots(snap, snap)
		end
	end)
end

----------------------------------------------------------------------
-- coins / level
----------------------------------------------------------------------
local function setCoins(target: number)
	if shownCoins < 0 then
		shownCoins = target
		coinLabel.Text = commas(target)
		return
	end
	local start = shownCoins
	if start == target then
		return
	end
	shownCoins = target
	if target > start then
		pop(coinScale, 1.15)
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.min(1, (os.clock() - t0) / 0.5)
		coinLabel.Text = commas(start + (target - start) * (1 - (1 - a) ^ 3))
		if a >= 1 then
			conn:Disconnect()
		end
	end)
end

local function attr(name: string, default: number): number
	local v = player:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local function refreshLevel()
	local lv = attr("RanchLevel", 1)
	local xp, xpMax = attr("RanchXP", 0), math.max(1, attr("RanchXPMax", 100))
	levelTitle.Text = `Ranch Lv. {lv}`
	levelNumber.Text = tostring(lv)
	tween(xpFill, 0.4, { Size = UDim2.fromScale(math.clamp(xp / xpMax, 0, 1), 1) })
	xpText.Text = `{commas(xp)} / {commas(xpMax)} XP`
	incomeLabel.Text = `+{commas(attr("CoinsPerSecond", 0))}/s`
end

local function refreshShopBadge(snap: { [string]: any })
	-- "!" when something in either shop is affordable right now
	local coins = snap.Coins
	local affordable = false
	for key, def in Config.VacUpgrades :: any do
		local price = def.Prices[(snap.Vac[key] or 1) + 1]
		if price and coins >= price then
			affordable = true
		end
	end
	local nextTier = Config.SecurityTiers[snap.Security + 1]
	if nextTier and coins >= nextTier.Price then
		affordable = true
	end
	if affordable and not shopBadge.Visible then
		shopBadge.Visible = true
		pop(shopBadge:FindFirstChildOfClass("UIScale") :: UIScale, 1.4)
	elseif not affordable then
		shopBadge.Visible = false
	end
end

function Hud.coinPop(amount: number)
	if amount > 0 then
		Sounds.play("Coin")
	end
	pop(coinScale, 1.25)
end

----------------------------------------------------------------------
-- toasts / fuel / reticle / equip
----------------------------------------------------------------------
local TOAST_COLORS = {
	info = Color3.fromRGB(235, 240, 250),
	good = Color3.fromRGB(140, 255, 170),
	warn = Color3.fromRGB(255, 210, 110),
	error = Color3.fromRGB(255, 130, 130),
	alarm = Color3.fromRGB(255, 90, 90),
	coins = Color3.fromRGB(255, 220, 110),
}

function Hud.toast(text: string, kind: string?)
	local color = TOAST_COLORS[kind or "info"] or TOAST_COLORS.info
	local t = new("Frame", { Size = UDim2.fromOffset(0, 42), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromRGB(58, 26, 110), BackgroundTransparency = 0.05 }, toastHolder)
	corner(t, 14)
	gradient(t, Color3.fromRGB(110, 50, 190), Color3.fromRGB(62, 26, 120))
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, t)
	local stroke = new("UIStroke", { Color = color, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, t)
	local l = label(t, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, TextScaled = false, TextSize = 24, TextColor3 = color, Text = text }, INK, 2.5)
	local scale = new("UIScale", { Scale = 0.6 }, t)
	tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	if kind == "alarm" then
		for k = 1, 4 do
			task.delay(k * 0.25, function()
				stroke.Transparency = if k % 2 == 0 then 0 else 0.8
			end)
		end
	end
	task.delay(3.2, function()
		tween(t, 0.3, { BackgroundTransparency = 1 })
		tween(l, 0.3, { TextTransparency = 1 })
		tween(stroke, 0.3, { Transparency = 1 })
		local ls = l:FindFirstChildOfClass("UIStroke")
		if ls then
			tween(ls, 0.3, { Transparency = 1 })
		end
		task.wait(0.32)
		t:Destroy()
	end)
	local children = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(children, c)
		end
	end
	if #children > 4 then
		children[1]:Destroy()
	end
end

function Hud.setFuel(frac: number, visible: boolean)
	fuelFrame.Visible = visible
	fuelFill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	fuelFill.BackgroundColor3 = if frac < 0.25 then Color3.fromRGB(255, 120, 90) else Color3.fromRGB(255, 200, 90)
end

function Hud.setReticle(screenPos: Vector2?, vacuuming: boolean)
	if not screenPos or not equipped then
		reticle.Visible = false
		return
	end
	reticle.Visible = true
	reticle.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	reticleScale.Scale = if vacuuming then 0.75 + math.sin(os.clock() * 18) * 0.06 else 1
	reticle.Rotation = if vacuuming then (os.clock() * 360) % 360 else 0
end

function Hud.setEquipped(on: boolean)
	equipped = on
	mobileButtons.Visible = on and UserInputService.TouchEnabled
	if not on then
		reticle.Visible = false
	end
end

local function roundButton(name: string, text: string, size: number, pos: UDim2, top: Color3, bottom: Color3): TextButton
	local b = new("TextButton", { Name = name, Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(1, 1), Position = pos, BackgroundColor3 = bottom, Text = "", AutoButtonColor = false }, mobileButtons)
	corner(b)
	gradient(b, top, bottom)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	label(b, { Size = UDim2.fromScale(0.7, 0.32), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Text = text })
	new("UIScale", {}, b)
	return b
end

local function refreshLock()
	local snap = ClientState.Data
	local idx = if snap then snap.PlotIndex else 0
	local root = Workspace:FindFirstChild("RanchPlots")
	local model = idx and idx > 0 and root and root:FindFirstChild(`Plot{idx}`)
	if model and model:GetAttribute("Locked") then
		local left = math.max(0, math.ceil(((model:GetAttribute("LockEnds") or 0) :: number) - Workspace:GetServerTimeNow()))
		lockChip.Visible = true
		lockChip.Text = `Gate locked · {left}s`
		lockChip.TextColor3 = if left <= 10 then Color3.fromRGB(255, 210, 110) else Color3.new(1, 1, 1)
	else
		lockChip.Visible = false
	end
end

local function invitePressed()
	local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and canInvite then
		pcall(SocialService.PromptGameInvite, SocialService, player)
	else
		Hud.toast("Invites aren't available right now", "warn")
	end
end

----------------------------------------------------------------------
function Hud.init()
	gui = new("ScreenGui", { Name = "RanchHud", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets }, player:WaitForChild("PlayerGui"))
	local uiScale = new("UIScale", {}, gui)
	local function rescale()
		local cam = Workspace.CurrentCamera
		local h = if cam then cam.ViewportSize.Y else 800
		uiScale.Scale = math.clamp(h / 900, 0.5, 1.1)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-------------------------------------------------- level bar (top centre)
	local level = new("Frame", { Name = "Level", Size = UDim2.fromOffset(530, 118), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), BackgroundTransparency = 1 }, gui)
	local pill = new("Frame", { Name = "Bar", Size = UDim2.fromOffset(400, 66), Position = UDim2.fromOffset(78, 42) }, level)
	goo(pill, { Blobs = 8, Drips = 2 })
	local track = new("Frame", { Size = UDim2.new(1, -110, 0, 30), Position = UDim2.fromOffset(34, 20), BackgroundColor3 = Color3.fromRGB(28, 22, 70), ZIndex = 2 }, pill)
	corner(track)
	new("UIStroke", { Color = Color3.fromRGB(18, 10, 44), Thickness = 2.5 }, track)
	xpFill = new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = CYAN, ZIndex = 3 }, track)
	corner(xpFill)
	gradient(xpFill, Color3.fromRGB(150, 235, 255), Color3.fromRGB(40, 150, 245))
	xpText = label(track, { Size = UDim2.new(1, -16, 0.8, 0), Position = UDim2.fromScale(0.03, 0.1), Text = "", ZIndex = 4 }, INK, 2.5)
	levelTitle = label(level, { Size = UDim2.fromOffset(300, 44), Position = UDim2.fromOffset(120, 0), Text = "Ranch Lv. 1", TextXAlignment = Enum.TextXAlignment.Left }, INK, 3.5)
	-- star badge (two rotated rounded squares make an 8-point seal)
	local star = new("Frame", { Name = "Star", Size = UDim2.fromOffset(104, 104), Position = UDim2.fromOffset(18, 12), BackgroundTransparency = 1, ZIndex = 5 }, level)
	if Config.UI.Icons.LevelStar ~= "" then
		new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Config.UI.Icons.LevelStar, ZIndex = 5 }, star)
	else
		for _, rot in { 0, 45 } do
			local sq = new("Frame", { Size = UDim2.fromScale(0.74, 0.74), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = rot, BackgroundColor3 = Color3.fromRGB(70, 175, 255), ZIndex = 5 }, star)
			corner(sq, 14)
			gradient(sq, Color3.fromRGB(140, 220, 255), Color3.fromRGB(40, 120, 235))
			new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sq)
		end
	end
	levelNumber = label(star, { Size = UDim2.fromScale(0.6, 0.48), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Text = "1", ZIndex = 7 }, Color3.fromRGB(20, 60, 140), 4)
	-- slime face on the right end
	local face = new("Frame", { Name = "Face", Size = UDim2.fromOffset(84, 78), Position = UDim2.fromOffset(440, 34), BackgroundColor3 = Color3.fromRGB(255, 120, 200), ZIndex = 5 }, level)
	if Config.UI.Icons.SlimeFace ~= "" then
		face.BackgroundTransparency = 1
		new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Config.UI.Icons.SlimeFace, ZIndex = 5 }, face)
	else
		corner(face, 34)
		gradient(face, Color3.fromRGB(255, 170, 225), Color3.fromRGB(240, 90, 180))
		new("UIStroke", { Color = Color3.fromRGB(255, 220, 245), Thickness = 3 }, face)
		local nub = new("Frame", { Size = UDim2.fromOffset(22, 26), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 6, 0, 8), BackgroundColor3 = Color3.fromRGB(255, 160, 220), ZIndex = 4 }, face)
		corner(nub)
		for _, x in { 0.36, 0.64 } do
			local eye = new("Frame", { Size = UDim2.fromScale(0.12, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), BackgroundColor3 = INK, ZIndex = 6 }, face)
			corner(eye)
		end
	end
	lockChip = label(level, { Size = UDim2.fromOffset(220, 26), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 10, 1, 0), Text = "", Visible = false }, Config.Fence.LockColor, 3)

	-------------------------------------------------- left menu
	local left = new("Frame", { Name = "Menu", Size = UDim2.fromOffset(112, 0), AutomaticSize = Enum.AutomaticSize.Y, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 20), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, left)
	local shop, shopHolder = menuButton(left, 1, "Shop", "🏪", "Shop", Color3.fromRGB(255, 200, 70), Color3.fromRGB(255, 120, 30))
	shopBadge = new("Frame", { Name = "Alert", Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), BackgroundColor3 = Color3.fromRGB(235, 40, 50), Visible = false, ZIndex = 8 }, shopHolder)
	corner(shopBadge)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, shopBadge)
	new("UIScale", {}, shopBadge)
	label(shopBadge, { Size = UDim2.fromScale(0.7, 0.75), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Text = "!", ZIndex = 9 }, INK, 2)
	shop.Activated:Connect(function()
		shopPressed:Fire()
	end)
	local index = menuButton(left, 2, "Index", "📖", "Index", Color3.fromRGB(200, 120, 255), Color3.fromRGB(125, 55, 225), true)
	index.Activated:Connect(function()
		indexPressed:Fire()
	end)
	local invite = menuButton(left, 3, "Invite", "👥", "Invite", Color3.fromRGB(110, 220, 255), Color3.fromRGB(35, 135, 245))
	invite.Activated:Connect(invitePressed)

	-------------------------------------------------- right column
	local right = new("Frame", { Name = "Travel", Size = UDim2.fromOffset(112, 0), AutomaticSize = Enum.AutomaticSize.Y, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, if TOUCH then 0.4 else 0.5, 0), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, right)
	local hover = menuButton(right, 1, "Hoverboard", "🛹", nil, Color3.fromRGB(215, 120, 255), Color3.fromRGB(135, 55, 225), true)
	hover.Activated:Connect(function()
		hoverPressed:Fire()
	end)
	local jet, jetHolder = menuButton(right, 2, "Jetpack", "🚀", nil, Color3.fromRGB(120, 215, 255), Color3.fromRGB(40, 130, 245))
	jet.Activated:Connect(function()
		jetPressed:Fire()
	end)
	fuelFrame = new("Frame", { Name = "Fuel", Size = UDim2.new(1, -16, 0, 10), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 6), BackgroundColor3 = INK, Visible = false }, jetHolder)
	corner(fuelFrame)
	fuelFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 200, 90), BorderSizePixel = 0 }, fuelFrame)
	corner(fuelFill)
	local home = menuButton(right, 3, "Home", "🏠", nil, Color3.fromRGB(150, 240, 110), Color3.fromRGB(55, 180, 60))
	home.Activated:Connect(function()
		homePressed:Fire()
	end)

	-------------------------------------------------- settings (top right)
	local settings = new("TextButton", { Name = "Settings", Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), BackgroundColor3 = Color3.fromRGB(25, 30, 45), BackgroundTransparency = 0.15, Text = "" }, gui)
	corner(settings)
	icon(settings, "Settings", "⚙️", UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5))
	settings.Activated:Connect(function()
		settingsPressed:Fire()
	end)

	-------------------------------------------------- coins (bottom left / top left on touch)
	local money = new("Frame", {
		Name = "Money",
		Size = UDim2.fromOffset(320, 116),
		AnchorPoint = if TOUCH then Vector2.new(0, 0) else Vector2.new(0, 1),
		Position = if TOUCH then UDim2.fromOffset(16, 70) else UDim2.new(0, 22, 1, -18),
		BackgroundTransparency = 1,
	}, gui)
	coinScale = new("UIScale", {}, money)
	local coinIcon = new("Frame", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(0, 4), BackgroundColor3 = Color3.fromRGB(165, 70, 235) }, money)
	if Config.UI.Icons.Coin ~= "" then
		coinIcon.BackgroundTransparency = 1
		new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Config.UI.Icons.Coin }, coinIcon)
	else
		corner(coinIcon)
		gradient(coinIcon, Color3.fromRGB(205, 120, 255), Color3.fromRGB(130, 45, 215))
		new("UIStroke", { Color = Color3.fromRGB(240, 190, 255), Thickness = 3 }, coinIcon)
		local inner = new("Frame", { Size = UDim2.fromScale(0.62, 0.62), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(120, 35, 205) }, coinIcon)
		corner(inner)
		for _, x in { 0.36, 0.64 } do
			local eye = new("Frame", { Size = UDim2.fromScale(0.16, 0.24), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), BackgroundColor3 = Color3.fromRGB(235, 200, 255) }, inner)
			corner(eye)
		end
	end
	coinLabel = label(money, { Size = UDim2.fromOffset(250, 58), Position = UDim2.fromOffset(66, 2), Text = "0", TextXAlignment = Enum.TextXAlignment.Left }, INK, 4)
	icon(money, "Income", "⬆️", UDim2.fromOffset(40, 40), UDim2.fromOffset(28, 86))
	incomeLabel = label(money, { Size = UDim2.fromOffset(220, 44), Position = UDim2.fromOffset(66, 64), Text = "+0/s", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(140, 255, 80) }, Color3.fromRGB(20, 70, 12), 3.5)

	-------------------------------------------------- hotbar (bottom centre)
	-- outer frame sizes itself from the slot row; the goo body fills it behind
	local bar = new("Frame", { Name = "Hotbar", Size = UDim2.fromOffset(0, 112), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), BackgroundTransparency = 1 }, gui)
	local body = new("Frame", { Name = "Goo", Size = UDim2.fromScale(1, 1), ZIndex = 1 }, bar)
	goo(body, { Radius = 40, Blobs = 14, Drips = 4 })
	hotbar = new("Frame", { Name = "Slots", Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 2 }, bar)
	new("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 10) }, hotbar)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, hotbar)

	-------------------------------------------------- toasts
	toastHolder = new("Frame", { Name = "Toasts", Size = UDim2.new(1, 0, 0, 240), Position = UDim2.fromOffset(0, 150), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)

	-------------------------------------------------- reticle (own unscaled gui so it tracks the mouse)
	local reticleGui = new("ScreenGui", { Name = "RanchReticle", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 10 }, player:WaitForChild("PlayerGui"))
	reticle = new("Frame", { Name = "Reticle", Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false }, reticleGui)
	reticleScale = new("UIScale", {}, reticle)
	corner(reticle)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2.5, Transparency = 0.15 }, reticle)
	for _, spec in { { 0.5, 0, 3, 8 }, { 0.5, 1, 3, 8 }, { 0, 0.5, 8, 3 }, { 1, 0.5, 8, 3 } } do
		new("Frame", { Size = UDim2.fromOffset(spec[3], spec[4]), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spec[1], spec[2]), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, reticle)
	end
	local dot = new("Frame", { Size = UDim2.fromOffset(5, 5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, reticle)
	corner(dot)

	-------------------------------------------------- mobile vac controls
	mobileButtons = new("Frame", { Name = "Mobile", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)
	local vacButton = roundButton("Vac", "VAC", 116, UDim2.new(1, -24, 1, -200), Color3.fromRGB(150, 235, 255), Color3.fromRGB(40, 150, 245))
	local shootButton = roundButton("Shoot", "SHOOT", 90, UDim2.new(1, -156, 1, -160), Color3.fromRGB(255, 170, 220), Color3.fromRGB(230, 70, 160))
	vacButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			pop(vacButton:FindFirstChildOfClass("UIScale") :: UIScale, 0.88)
			vacBegan:Fire()
		end
	end)
	vacButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			vacEnded:Fire()
		end
	end)
	shootButton.Activated:Connect(function()
		pop(shootButton:FindFirstChildOfClass("UIScale") :: UIScale, 0.85)
		shootPressed:Fire()
	end)

	-------------------------------------------------- data
	local function onState(snap: { [string]: any }, prev: { [string]: any }?)
		refreshSlots(snap, prev)
		local override = player:GetAttribute("Coins")
		setCoins(if typeof(override) == "number" then override else snap.Coins)
		refreshShopBadge(snap)
		refreshLock()
	end
	ClientState.Changed:Connect(onState)
	if ClientState.Data then
		onState(ClientState.Data, nil)
	end
	for _, a in { "RanchLevel", "RanchXP", "RanchXPMax", "CoinsPerSecond" } do
		player:GetAttributeChangedSignal(a):Connect(refreshLevel)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		local v = player:GetAttribute("Coins")
		if typeof(v) == "number" then
			setCoins(v)
		end
	end)
	refreshLevel()
	task.spawn(function()
		while true do
			task.wait(0.25)
			refreshLock()
		end
	end)
end

return Hud
