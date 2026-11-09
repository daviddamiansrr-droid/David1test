--!strict
-- Local vac input + feel. Sends intent only; the server decides what gets sucked.
--
-- PC:      hold LMB = vac, tap RMB or F = shoot, 1-5 = slot, Q = next slot
-- Gamepad: hold R2 = vac, L2 = shoot, DPad left/right = slot
-- Mobile:  on-screen VAC (hold) / SHOOT (tap), tap a slot to select
--
-- Juice: instant local suction start (no waiting on the server), recoil spring
-- on the camera, FOV push while vacuuming, rising-pitch absorb combo, slot
-- bounce, fill gauge on the tool, character turns to face the aim.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)
local Sounds = require(script.Parent.Sounds)
local VacFx = require(script.Parent.VacFx)

local player = Players.LocalPlayer
local VacInput = Remotes.event("VacInput")

local VacController = {}

local tool: Tool? = nil
local vacHeld = false
local aimDir = Vector3.new(0, 0, -1)
local lastSentDir = Vector3.zero
local lastAimSent = 0
local lastShot = 0
local faceUntil = 0
local usingPointer = UserInputService.MouseEnabled and not UserInputService.TouchEnabled
local rmbDownAt = 0
local rmbDownPos = Vector2.zero

-- camera feel
local recoil, recoilVel = 0, 0
local shake = 0
local fovKick = 0
local fovBlend = 0
local baseFov = 70
local applied = CFrame.new()

-- absorb combo
local streak = 0
local lastAbsorb = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function character(): Model?
	return player.Character
end

local function humanoid(): Humanoid?
	local c = character()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function aim(): (Vector3, Vector2?)
	local cam = Workspace.CurrentCamera
	local char = character()
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not cam or not head or not char then
		return aimDir, nil
	end
	local screen: Vector2
	if usingPointer then
		screen = UserInputService:GetMouseLocation()
	else
		local vp = cam.ViewportSize
		screen = Vector2.new(vp.X * 0.5, vp.Y * 0.42)
	end
	local ray = cam:ViewportPointToRay(screen.X, screen.Y)
	rayParams.FilterDescendantsInstances = { char, Workspace:FindFirstChild("Items") :: Instance }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 400, rayParams)
	local target = if hit then hit.Position else ray.Origin + ray.Direction * 400
	local dir = target - head.Position
	if dir.Magnitude < 1 or dir.Unit:Dot(cam.CFrame.LookVector) < -0.2 then
		dir = cam.CFrame.LookVector
	end
	local inset = GuiService:GetGuiInset()
	return dir.Unit, screen - inset
end

local function selectedSlot(): (number, { Id: string?, Count: number }?)
	local snap = ClientState.Data
	if not snap then
		return 1, nil
	end
	return snap.Selected, snap.Tank[snap.Selected]
end

local function updateFluid()
	if not tool then
		return
	end
	local fluid = tool:FindFirstChild("Fluid") :: BasePart?
	local snap = ClientState.Data
	if not fluid or not snap then
		return
	end
	local _, slot = selectedSlot()
	local frac = if slot then slot.Count / snap.TankCap else 0
	fluid.Size = Vector3.new(0.05 + 1.55 * frac, fluid.Size.Y, fluid.Size.Z)
	fluid.Color = if slot and slot.Id then (ItemIds.colors(slot.Id)) else Config.Fence.Color
	fluid.Transparency = if frac > 0 then 0.1 else 1
end

----------------------------------------------------------------------
-- actions
----------------------------------------------------------------------
local function startVac()
	if not tool or vacHeld then
		return
	end
	vacHeld = true
	aimDir = aim()
	tool:SetAttribute("VacOn", true) -- local prediction so particles start instantly
	VacInput:FireServer("start", aimDir)
	lastSentDir = aimDir
	local hum = humanoid()
	if hum then
		hum.AutoRotate = false
	end
end

local function stopVac()
	if not vacHeld then
		return
	end
	vacHeld = false
	if tool then
		tool:SetAttribute("VacOn", false)
	end
	VacInput:FireServer("stop")
	local hum = humanoid()
	if hum and os.clock() > faceUntil then
		hum.AutoRotate = true
	end
end

local function shoot()
	if not tool then
		return
	end
	local t = os.clock()
	if t - lastShot < Config.Vac.ShootCooldown then
		return
	end
	local index, slot = selectedSlot()
	if not slot or not slot.Id or slot.Count <= 0 then
		Hud.denySlot(index)
		Sounds.play("Full", 0.35, 0.6)
		return
	end
	lastShot = t
	aimDir = aim()
	VacInput:FireServer("shoot", aimDir)

	-- predicted juice
	local fx = VacFx.toolOf(player)
	if fx then
		VacFx.muzzle(fx, (ItemIds.colors(slot.Id)))
	end
	Sounds.play("Shoot", 0.55, 1.25 + math.random() * 0.15)
	recoilVel += 2.4
	shake += 0.006
	fovKick -= 2
	Hud.bounceSlot(index)
	faceUntil = t + 0.5
	local hum = humanoid()
	if hum then
		hum.AutoRotate = false
	end
end

local function selectSlot(i: number)
	local snap = ClientState.Data
	if not snap or i < 1 or i > #snap.Tank or i == snap.Selected then
		return
	end
	VacInput:FireServer("select", i)
	snap.Selected = i -- optimistic; next server snapshot confirms
	Sounds.play("Button", 0.3, 1.4)
	Hud.bounceSlot(i)
	updateFluid()
end

local function cycle(step: number)
	local snap = ClientState.Data
	if not snap then
		return
	end
	local n = #snap.Tank
	selectSlot(((snap.Selected - 1 + step) % n) + 1)
end

VacFx.onLocalAbsorb = function(id: string)
	local t = os.clock()
	streak = if t - lastAbsorb < 0.6 then streak + 1 else 0
	lastAbsorb = t
	Sounds.play("Absorb", 0.45, 1 + math.min(streak, 12) * 0.06)
	shake += 0.0035
	fovKick += 1.2
	local snap = ClientState.Data
	if snap then
		for i, s in snap.Tank do
			if s.Id == id then
				Hud.bounceSlot(i)
				return
			end
		end
		-- new item type: it'll land in the first empty slot
		for i, s in snap.Tank do
			if s.Count <= 0 then
				Hud.bounceSlot(i)
				return
			end
		end
	end
end

----------------------------------------------------------------------
-- equip tracking
----------------------------------------------------------------------
local function setTool(t: Tool?)
	if tool == t then
		return
	end
	if not t then
		stopVac()
	end
	tool = t
	Hud.setEquipped(t ~= nil)
	UserInputService.MouseIconEnabled = not (t ~= nil and usingPointer)
	local hum = humanoid()
	if hum and not t then
		hum.AutoRotate = true
	end
	updateFluid()
end

local function hookCharacter(char: Model)
	setTool(nil)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") and c.Name == Config.Vac.ToolName then
			setTool(c)
		end
	end)
	char.ChildRemoved:Connect(function(c)
		if c == tool then
			setTool(nil)
		end
	end)
	local existing = char:FindFirstChild(Config.Vac.ToolName)
	if existing and existing:IsA("Tool") then
		setTool(existing)
	end
end

----------------------------------------------------------------------
function VacController.init()
	local cam = Workspace.CurrentCamera
	baseFov = if cam then cam.FieldOfView else 70

	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)

	UserInputService.LastInputTypeChanged:Connect(function(t)
		if t == Enum.UserInputType.Touch or t.Name:sub(1, 7) == "Gamepad" then
			usingPointer = false
		elseif t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Keyboard then
			usingPointer = UserInputService.MouseEnabled
		end
		UserInputService.MouseIconEnabled = not (tool ~= nil and usingPointer)
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if not tool then
			return
		end
		local t = input.UserInputType
		local k = input.KeyCode
		if t == Enum.UserInputType.MouseButton1 and not gpe then
			startVac()
		elseif t == Enum.UserInputType.MouseButton2 then
			rmbDownAt = os.clock()
			rmbDownPos = UserInputService:GetMouseLocation()
		elseif gpe then
			return
		elseif k == Enum.KeyCode.F or k == Enum.KeyCode.ButtonL2 then
			shoot()
		elseif k == Enum.KeyCode.ButtonR2 then
			startVac()
		elseif k == Enum.KeyCode.Q or k == Enum.KeyCode.DPadRight then
			cycle(1)
		elseif k == Enum.KeyCode.DPadLeft then
			cycle(-1)
		else
			local n = k.Value - Enum.KeyCode.One.Value + 1
			if n >= 1 and n <= 5 then
				selectSlot(n)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			stopVac()
		elseif t == Enum.UserInputType.MouseButton2 and tool then
			-- quick click = shoot; a drag is the player rotating the camera
			local moved = (UserInputService:GetMouseLocation() - rmbDownPos).Magnitude
			if os.clock() - rmbDownAt < 0.25 and moved < 8 then
				shoot()
			end
		end
	end)

	Hud.MobileVacBegan:Connect(startVac)
	Hud.MobileVacEnded:Connect(stopVac)
	Hud.MobileShoot:Connect(shoot)
	Hud.SlotPressed:Connect(selectSlot)
	ClientState.Changed:Connect(updateFluid)

	-- camera offset is removed before the camera module runs and re-applied
	-- after, so recoil never accumulates into the player's actual camera angle
	RunService:BindToRenderStep("VacCamUndo", Enum.RenderPriority.Camera.Value - 1, function()
		local c = Workspace.CurrentCamera
		if c and applied ~= CFrame.identity then
			c.CFrame = c.CFrame * applied:Inverse()
			applied = CFrame.identity
		end
	end)
	RunService:BindToRenderStep("VacCamApply", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local c = Workspace.CurrentCamera
		if not c then
			return
		end
		-- recoil spring
		local accel = -recoil * 140 - recoilVel * 16
		recoilVel += accel * dt
		recoil += recoilVel * dt
		shake = math.max(0, shake - dt * 0.05)
		local sx = (math.random() - 0.5) * shake
		local sy = (math.random() - 0.5) * shake
		applied = CFrame.Angles(recoil * 0.05 + sx, sy, 0)
		c.CFrame = c.CFrame * applied

		fovBlend += ((if vacHeld then 1 else 0) - fovBlend) * math.min(1, dt * 8)
		fovKick += (0 - fovKick) * math.min(1, dt * 10)
		c.FieldOfView = baseFov + fovBlend * 5 + fovKick
	end)

	RunService.RenderStepped:Connect(function()
		if not tool then
			Hud.setReticle(nil, false)
			return
		end
		local dir, screen = aim()
		aimDir = dir
		Hud.setReticle(screen, vacHeld)

		local t = os.clock()
		if vacHeld and t - lastAimSent > 0.07 and dir:Dot(lastSentDir) < math.cos(math.rad(1.5)) then
			lastAimSent = t
			lastSentDir = dir
			VacInput:FireServer("aim", dir)
		end

		-- face where you're aiming while vacuuming / just after a shot
		local char = character()
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (vacHeld or t < faceUntil) then
			local flatDir = Vector3.new(dir.X, 0, dir.Z)
			if flatDir.Magnitude > 0.1 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flatDir)
			end
		elseif not vacHeld and t >= faceUntil then
			local hum = humanoid()
			if hum and not hum.AutoRotate then
				hum.AutoRotate = true
			end
		end
	end)
end

return VacController
