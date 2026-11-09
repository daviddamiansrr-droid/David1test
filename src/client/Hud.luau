--!strict
-- HUD built entirely in code (no image assets):
--   bottom: tank slots with fill bars, selected slot glow, bounce on absorb
--   top-right: coins (count-up + pop) and Gem Bank
--   top-left: your ranch status (tier, gate lock countdown)
--   top-center: toasts
--   mobile: big VAC (hold) and SHOOT (tap) buttons, tap slots to select
--   reticle that follows your aim while the vac is out

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)
local ClientState = require(script.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local ACCENT = Config.Fence.Color
local PANEL = Color3.fromRGB(22, 28, 44)

local Hud = {}

local gui: ScreenGui
local slotBar: Frame
local slots: { { Root: Frame, Scale: UIScale, Stroke: UIStroke, Icon: Frame, Count: TextLabel, Fill: Frame, Key: TextLabel } } = {}
local coinLabel: TextLabel
local coinScale: UIScale
local bankLabel: TextLabel
local ranchTitle: TextLabel
local ranchGate: TextLabel
local toastHolder: Frame
local fuelFrame: Frame
local fuelFill: Frame
local reticle: Frame
local reticleScale: UIScale
local mobileButtons: Frame
local shownCoins = 0
local equipped = false

local vacBegan = Instance.new("BindableEvent")
local vacEnded = Instance.new("BindableEvent")
local shootPressed = Instance.new("BindableEvent")
local slotPressed = Instance.new("BindableEvent")
Hud.MobileVacBegan = vacBegan.Event
Hud.MobileVacEnded = vacEnded.Event
Hud.MobileShoot = shootPressed.Event
Hud.SlotPressed = slotPressed.Event

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
	new("UICorner", { CornerRadius = UDim.new(0, r or 14) }, parent)
end

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function pop(scale: UIScale, amount: number?)
	scale.Scale = amount or 1.25
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

----------------------------------------------------------------------
-- item icons (pure frames)
----------------------------------------------------------------------
local function paintIcon(icon: Frame, id: string?)
	for _, c in icon:GetChildren() do
		c:Destroy()
	end
	if not id then
		icon.Visible = false
		return
	end
	icon.Visible = true
	local parsed = ItemIds.parse(id)
	local a, b = ItemIds.colors(id)
	icon.BackgroundColor3 = a
	icon.Rotation = 0
	if parsed and parsed.Kind == "gem" then
		icon.Rotation = 45
		corner(icon, 6)
		new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.4, Thickness = 2 }, icon)
	else
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, icon)
	end
	if b then
		new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.5, a), ColorSequenceKeypoint.new(0.51, b), ColorSequenceKeypoint.new(1, b) }), Rotation = 90 }, icon)
	end
	if parsed and parsed.Kind == "slime" then
		for _, x in { 0.32, 0.68 } do
			local eye = new("Frame", { Size = UDim2.fromScale(0.16, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.42), BackgroundColor3 = Color3.fromRGB(30, 25, 40), BorderSizePixel = 0 }, icon)
			corner(eye, 99)
		end
	end
end

----------------------------------------------------------------------
-- slot bar
----------------------------------------------------------------------
local function buildSlot(i: number)
	local root = new("Frame", { Name = `Slot{i}`, Size = UDim2.fromOffset(78, 78), BackgroundColor3 = PANEL, BackgroundTransparency = 0.2, LayoutOrder = i }, slotBar)
	corner(root, 18)
	local stroke = new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.7, Thickness = 2 }, root)
	local scale = new("UIScale", {}, root)
	local icon = new("Frame", { Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), BorderSizePixel = 0, Visible = false }, root)
	local count = new("TextLabel", { Size = UDim2.fromOffset(40, 22), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -8), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, Text = "" }, root)
	local barBg = new("Frame", { Size = UDim2.new(1, -16, 0, 5), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, BorderSizePixel = 0 }, root)
	corner(barBg, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, barBg)
	corner(fill, 3)
	local key = new("TextLabel", { Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(6, 4), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = Color3.fromRGB(200, 210, 230), Text = tostring(i), Visible = not UserInputService.TouchEnabled }, root)
	local button = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, root)
	button.Activated:Connect(function()
		slotPressed:Fire(i)
	end)
	slots[i] = { Root = root, Scale = scale, Stroke = stroke, Icon = icon, Count = count, Fill = fill, Key = key }
end

local function refreshSlots(snap: { [string]: any }, prev: { [string]: any }?)
	local tank = snap.Tank :: { { Id: string?, Count: number } }
	for i = #slots + 1, #tank do
		buildSlot(i)
	end
	for i, s in slots do
		local data = tank[i]
		s.Root.Visible = data ~= nil
		if not data then
			continue
		end
		local prevSlot = prev and prev.Tank and prev.Tank[i]
		if not prevSlot or prevSlot.Id ~= data.Id then
			paintIcon(s.Icon, data.Id)
		end
		s.Count.Text = if data.Count > 0 then tostring(data.Count) else ""
		tween(s.Fill, 0.2, { Size = UDim2.fromScale(data.Count / snap.TankCap, 1) })
		s.Fill.BackgroundColor3 = if data.Count >= snap.TankCap then Color3.fromRGB(255, 190, 90) else ACCENT
		local selected = snap.Selected == i
		s.Stroke.Color = if selected then ACCENT else Color3.new(1, 1, 1)
		s.Stroke.Transparency = if selected then 0 else 0.7
		s.Stroke.Thickness = if selected then 4 else 2
		s.Root.BackgroundTransparency = if selected then 0.05 else 0.25
	end
end

function Hud.bounceSlot(i: number)
	local s = slots[i]
	if s then
		pop(s.Scale, 1.18)
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
-- coins / ranch / toasts / fuel / reticle / mobile
----------------------------------------------------------------------
local function setCoins(target: number)
	local start = shownCoins
	if start == target then
		return
	end
	shownCoins = target
	if target > start then
		pop(coinScale, 1.2)
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.min(1, (os.clock() - t0) / 0.5)
		coinLabel.Text = tostring(math.floor(start + (target - start) * (1 - (1 - a) ^ 3)))
		if a >= 1 then
			conn:Disconnect()
		end
	end)
end

function Hud.coinPop(amount: number)
	if amount > 0 then
		Sounds.play("Coin", 0.5, 1.3)
	end
	pop(coinScale, 1.3)
end

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
	local t = new("Frame", { Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = PANEL, BackgroundTransparency = 0.15 }, toastHolder)
	corner(t, 12)
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, t)
	local stroke = new("UIStroke", { Color = color, Thickness = 2, Transparency = 0.2 }, t)
	local label = new("TextLabel", { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = FONT, TextSize = 22, TextColor3 = color, Text = text }, t)
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
		tween(label, 0.3, { TextTransparency = 1 })
		tween(stroke, 0.3, { Transparency = 1 })
		task.wait(0.32)
		t:Destroy()
	end)
	-- never stack more than 4
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
	fuelFill.Size = UDim2.fromScale(1, math.clamp(frac, 0, 1))
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

local function roundButton(name: string, text: string, size: number, pos: UDim2, color: Color3): TextButton
	local b = new("TextButton", { Name = name, Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(1, 1), Position = pos, BackgroundColor3 = color, BackgroundTransparency = 0.15, Font = FONT, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = text, AutoButtonColor = false }, mobileButtons)
	corner(b, 999)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	new("UIPadding", { PaddingTop = UDim.new(0.3, 0), PaddingBottom = UDim.new(0.3, 0), PaddingLeft = UDim.new(0.15, 0), PaddingRight = UDim.new(0.15, 0) }, b)
	new("UIScale", {}, b)
	return b
end

local function refreshRanch()
	local snap = ClientState.Data
	local idx = if snap then snap.PlotIndex else 0
	if not idx or idx == 0 then
		ranchTitle.Text = "No ranch"
		ranchGate.Text = ""
		return
	end
	local tier = Config.SecurityTiers[snap and snap.Security or 1]
	ranchTitle.Text = `Ranch {idx} · {tier.Name}`
	local root = Workspace:FindFirstChild("RanchPlots")
	local model = root and root:FindFirstChild(`Plot{idx}`)
	if model and model:GetAttribute("Locked") then
		local left = math.max(0, math.ceil(((model:GetAttribute("LockEnds") or 0) :: number) - Workspace:GetServerTimeNow()))
		ranchGate.Text = `Gate LOCKED · {left}s`
		ranchGate.TextColor3 = if left <= 10 then Color3.fromRGB(255, 200, 110) else Config.Fence.LockColor
	else
		ranchGate.Text = "Gate OPEN · lock it at your console"
		ranchGate.TextColor3 = Color3.fromRGB(150, 255, 190)
	end
end

function Hud.init()
	gui = new("ScreenGui", { Name = "RanchHud", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	local uiScale = new("UIScale", {}, gui)
	local function rescale()
		local cam = Workspace.CurrentCamera
		local h = if cam then cam.ViewportSize.Y else 800
		uiScale.Scale = math.clamp(h / 820, 0.62, 1.15)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	slotBar = new("Frame", { Name = "Slots", AutomaticSize = Enum.AutomaticSize.XY, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }, slotBar)

	fuelFrame = new("Frame", { Name = "Fuel", Size = UDim2.fromOffset(12, 78), BackgroundColor3 = PANEL, BackgroundTransparency = 0.2, LayoutOrder = 99, Visible = false }, slotBar)
	corner(fuelFrame, 6)
	fuelFill = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 200, 90), BorderSizePixel = 0 }, fuelFrame)
	corner(fuelFill, 6)

	-- coins
	local coinBox = new("Frame", { Name = "Coins", Size = UDim2.fromOffset(200, 50), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), BackgroundColor3 = PANEL, BackgroundTransparency = 0.2 }, gui)
	corner(coinBox, 16)
	coinScale = new("UIScale", {}, coinBox)
	local coin = new("Frame", { Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(10, 9), BackgroundColor3 = Color3.fromRGB(255, 205, 70) }, coinBox)
	corner(coin, 99)
	new("UIStroke", { Color = Color3.fromRGB(255, 240, 170), Thickness = 3 }, coin)
	coinLabel = new("TextLabel", { Size = UDim2.new(1, -56, 1, -12), Position = UDim2.fromOffset(50, 6), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 230, 140), Text = "0" }, coinBox)
	bankLabel = new("TextLabel", { Size = UDim2.fromOffset(200, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 64), BackgroundTransparency = 1, Font = FONT, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(200, 230, 255), TextStrokeTransparency = 0.6, Text = "" }, gui)

	-- ranch status
	local ranch = new("Frame", { Name = "Ranch", Size = UDim2.fromOffset(300, 56), Position = UDim2.fromOffset(14, 10), BackgroundColor3 = PANEL, BackgroundTransparency = 0.25 }, gui)
	corner(ranch, 14)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, ranch)
	ranchTitle = new("TextLabel", { Size = UDim2.fromScale(1, 0.55), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), Text = "" }, ranch)
	ranchGate = new("TextLabel", { Size = UDim2.fromScale(1, 0.45), Position = UDim2.fromScale(0, 0.55), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = ACCENT, Text = "" }, ranch)

	-- toasts
	toastHolder = new("Frame", { Name = "Toasts", Size = UDim2.new(1, 0, 0, 220), Position = UDim2.fromOffset(0, 74), BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)

	-- reticle lives in its own unscaled ScreenGui so it lines up with the mouse exactly
	local reticleGui = new("ScreenGui", { Name = "RanchReticle", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 10 }, player:WaitForChild("PlayerGui"))
	reticle = new("Frame", { Name = "Reticle", Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false }, reticleGui)
	reticleScale = new("UIScale", {}, reticle)
	corner(reticle, 99)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2.5, Transparency = 0.15 }, reticle)
	for _, spec in { { 0.5, 0, 3, 8 }, { 0.5, 1, 3, 8 }, { 0, 0.5, 8, 3 }, { 1, 0.5, 8, 3 } } do
		new("Frame", { Size = UDim2.fromOffset(spec[3], spec[4]), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spec[1], spec[2]), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, reticle)
	end
	local dot = new("Frame", { Size = UDim2.fromOffset(5, 5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, reticle)
	corner(dot, 99)

	-- mobile controls
	mobileButtons = new("Frame", { Name = "Mobile", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)
	local vacButton = roundButton("Vac", "VAC", 104, UDim2.new(1, -20, 1, -190), ACCENT)
	local shootButton = roundButton("Shoot", "SHOOT", 80, UDim2.new(1, -140, 1, -150), Color3.fromRGB(255, 150, 120))
	vacButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			vacButton.BackgroundTransparency = 0
			vacBegan:Fire()
		end
	end)
	vacButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			vacButton.BackgroundTransparency = 0.15
			vacEnded:Fire()
		end
	end)
	shootButton.Activated:Connect(function()
		pop(shootButton:FindFirstChildOfClass("UIScale") :: UIScale, 0.85)
		shootPressed:Fire()
	end)

	local function onState(snap: { [string]: any }, prev: { [string]: any }?)
		refreshSlots(snap, prev)
		setCoins(snap.Coins)
		local bank = 0
		for _, n in snap.Bank do
			bank += n
		end
		bankLabel.Text = if bank > 0 then `Gem Bank: {bank}` else ""
		refreshRanch()
	end
	ClientState.Changed:Connect(onState)
	if ClientState.Data then
		onState(ClientState.Data, nil) -- snapshot may have arrived before init
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			refreshRanch()
		end
	end)
end

return Hud
