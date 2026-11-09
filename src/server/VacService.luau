--!strict
-- The vac: server-authoritative suck + shoot.
--
-- Client only sends intent (start/stop, aim direction, shoot, select slot).
-- Server decides what is in range, checks line of sight against other players'
-- energy walls, pulls objects physically, and owns the tank contents.
-- All feel/juice (particles, sounds, camera kick, slot bounce) is client-side,
-- driven by the Fx events fired here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemIds = require(ReplicatedStorage.Shared.ItemIds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ItemFactory = require(script.Parent.ItemFactory)
local PlotService = require(script.Parent.PlotService)
local StateSync = require(script.Parent.StateSync)

local V = Config.Vac
local FxRemote = Remotes.event("Fx")
local NotifyRemote = Remotes.event("Notify")

type VacState = {
	On: boolean,
	Dir: Vector3,
	AimWindowStart: number,
	AimCount: number,
	LastShot: number,
	LastAbsorb: number,
	LastJet: number,
	FullWarnAt: number,
}

local VacService = {}
local states: { [Player]: VacState } = {}

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = { ItemFactory.Slimes, ItemFactory.Items }

----------------------------------------------------------------------
-- validation helpers
----------------------------------------------------------------------
local function validDir(v: any): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local x, y, z = v.X, v.Y, v.Z
	if x ~= x or y ~= y or z ~= z then
		return nil -- NaN
	end
	local m = v.Magnitude
	if m < 0.1 or m > 1e4 then
		return nil
	end
	return v / m
end

local function equipped(player: Player): Tool?
	local char = player.Character
	local tool = char and char:FindFirstChild(V.ToolName)
	return if tool and tool:IsA("Tool") then tool else nil
end

local function nozzlePosition(player: Player, tool: Tool, dir: Vector3): Vector3?
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	local n = tool:FindFirstChild("Nozzle") :: BasePart?
	if n and (n.Position - head.Position).Magnitude <= V.MaxNozzleOffset then
		return n.Position
	end
	return head.Position + dir * 2.5
end

local function slotCount(d: DataService.Data): number
	return Config.VacUpgrades.Slots.Values[d.Vac.Slots]
end

local function tankCap(d: DataService.Data): number
	return Config.VacUpgrades.Tank.Values[d.Vac.Tank]
end

local function findSlot(d: DataService.Data, id: string): number?
	local cap = tankCap(d)
	local empty: number? = nil
	for i = 1, slotCount(d) do
		local s = d.Tank[i]
		if s and s.Id == id and s.Count < cap then
			return i
		end
		if (not s or s.Count <= 0) and not empty then
			empty = i
		end
	end
	return empty
end

----------------------------------------------------------------------
-- absorb / pull
----------------------------------------------------------------------
local function absorb(player: Player, d: DataService.Data, part: BasePart, slot: number)
	local id = part:GetAttribute("Id") :: string
	local kind = part:GetAttribute("Kind")
	local pos = part.Position

	if kind == "slime" then
		local idx = (part:GetAttribute("Plot") or 0) :: number
		local plot = PlotService.Plots[idx]
		if plot and plot.Owner and plot.Owner ~= player then
			PlotService.onStolen(plot, player, ItemIds.display(id))
		end
	end

	ItemFactory.objectOf(part):Destroy()
	local s = d.Tank[slot]
	if s and s.Id == id then
		s.Count += 1
	else
		d.Tank[slot] = { Id = id, Count = 1 }
	end
	StateSync.mark(player)
	FxRemote:FireAllClients("absorb", player, id, pos)
end

local function vacTick()
	local t = os.clock()
	for player, st in states do
		if not st.On then
			continue
		end
		local tool = equipped(player)
		local d = DataService.get(player)
		if not tool or not d then
			st.On = false
			-- unequipped mid-vac: the tool is in the backpack now, reset it there
			local backpack = player:FindFirstChildOfClass("Backpack")
			local stale = tool or (backpack and backpack:FindFirstChild(V.ToolName))
			if stale then
				stale:SetAttribute("VacOn", false)
			end
			continue
		end
		local origin = nozzlePosition(player, tool, st.Dir)
		if not origin then
			continue
		end
		local range = Config.VacUpgrades.Power.Values[d.Vac.Power]
		local pull = Config.VacUpgrades.Power.Pull[d.Vac.Power]
		local cosCone = math.cos(math.rad(V.ConeHalfAngle))

		local blockers = PlotService.losBlockers(player)
		local los: RaycastParams? = nil
		if #blockers > 0 then
			los = RaycastParams.new()
			los.FilterType = Enum.RaycastFilterType.Include
			los.FilterDescendantsInstances = blockers
		end

		local absorbed = false
		for _, p in Workspace:GetPartBoundsInRadius(origin, range, overlap) do
			local kind = p:GetAttribute("Kind")
			if not kind then
				continue
			end
			local to = p.Position - origin
			local dist = to.Magnitude
			if dist > V.CloseGrabRadius and st.Dir:Dot(to / dist) < cosCone then
				continue
			end
			if p:GetAttribute("ShooterId") == player.UserId
				and t - ((p:GetAttribute("ShotAt") or 0) :: number) < V.ReVacImmunity then
				continue
			end
			if los and Workspace:Raycast(origin, to, los) then
				continue -- energy wall in the way
			end
			local id = p:GetAttribute("Id")
			local slot = findSlot(d, id)
			if not slot then
				if t - st.FullWarnAt > 1.5 then
					st.FullWarnAt = t
					FxRemote:FireClient(player, "full", id)
				end
				continue
			end

			if dist <= V.AbsorbDistance + p.Size.Y / 2 then
				if not absorbed and t - st.LastAbsorb >= V.AbsorbInterval then
					absorbed = true
					st.LastAbsorb = t
					absorb(player, d, p, slot)
				end
			else
				-- pull toward the nozzle; faster when close for a snappy "slurp"
				local strength = pull * (0.6 + 0.6 * (1 - dist / range))
				p.AssemblyLinearVelocity = (-to / dist) * strength + Vector3.new(0, 2, 0)
				if ((p:GetAttribute("VacUntil") or 0) :: number) < t + 0.15 then
					p:SetAttribute("VacUntil", t + 0.35)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- input
----------------------------------------------------------------------
local function setOn(player: Player, st: VacState, on: boolean)
	st.On = on
	local tool = equipped(player)
	if tool then
		tool:SetAttribute("VacOn", on)
	end
end

local function shoot(player: Player, st: VacState, dir: Vector3)
	local t = os.clock()
	if t - st.LastShot < V.ShootCooldown then
		return
	end
	local tool = equipped(player)
	local d = DataService.get(player)
	if not tool or not d then
		return
	end
	local s = d.Tank[d.Selected]
	if not s or not s.Id or s.Count <= 0 then
		return
	end
	local parsed = ItemIds.parse(s.Id)
	if not parsed then
		return
	end
	if parsed.Kind == "slime" and ItemFactory.slimeCount() >= Config.World.MaxSlimes then
		NotifyRemote:FireClient(player, "Too many slimes out right now. Sell or corral some!", "error")
		return
	end
	if parsed.Kind ~= "slime" and ItemFactory.itemCount() >= Config.World.MaxItems + 20 then
		return
	end
	local origin = nozzlePosition(player, tool, dir)
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not origin or not rootPart then
		return
	end
	st.LastShot = t

	local id = s.Id :: string
	local spawnPos = origin + dir * 1.5
	local velocity = dir * V.ShootSpeed + rootPart.AssemblyLinearVelocity * 0.5
	local obj = ItemFactory.fromId(id, spawnPos, velocity)
	if not obj then
		return
	end
	local p: BasePart? = if obj:IsA("Model") then obj.PrimaryPart else obj :: any
	if p then
		p:SetAttribute("ShooterId", player.UserId)
		p:SetAttribute("ShotAt", t)
	end

	s.Count -= 1
	if s.Count <= 0 then
		d.Tank[d.Selected] = { Count = 0 }
	end
	StateSync.mark(player)
	FxRemote:FireAllClients("shoot", player, id)
end

local function onInput(player: Player, action: any, a1: any)
	local st = states[player]
	if not st or typeof(action) ~= "string" then
		return
	end
	if action == "start" then
		local dir = validDir(a1)
		if dir then
			st.Dir = dir
			setOn(player, st, true)
		end
	elseif action == "stop" then
		setOn(player, st, false)
	elseif action == "aim" then
		local t = os.clock()
		if t - st.AimWindowStart > 1 then
			st.AimWindowStart = t
			st.AimCount = 0
		end
		st.AimCount += 1
		if st.AimCount > V.AimRate then
			return
		end
		local dir = validDir(a1)
		if dir then
			st.Dir = dir
		end
	elseif action == "shoot" then
		local dir = validDir(a1)
		if dir then
			st.Dir = dir
			shoot(player, st, dir)
		end
	elseif action == "select" then
		local d = DataService.get(player)
		if d and typeof(a1) == "number" and a1 == a1 then
			local i = math.floor(a1)
			if i >= 1 and i <= slotCount(d) and i ~= d.Selected then
				d.Selected = i
				StateSync.mark(player)
			end
		end
	end
end

----------------------------------------------------------------------
-- the tool model (built in code so there are no assets to import)
----------------------------------------------------------------------
local function buildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = V.ToolName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Hold to vac, tap to shoot"
	tool.Grip = CFrame.new(0, -0.15, 0.35)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 1, 0.55)
	handle.Color = Color3.fromRGB(55, 60, 80)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = tool

	local function piece(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Transparency = transparency or 0
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		local w = Instance.new("WeldConstraint")
		w.Part0 = handle
		w.Part1 = p
		w.Parent = p
		p.Parent = tool
		return p
	end

	local alongZ = CFrame.Angles(0, math.pi / 2, 0) -- cylinders are X-aligned by default
	local white = Color3.fromRGB(240, 244, 250)
	local teal = Config.Fence.Color

	piece("Body", Enum.PartType.Block, Vector3.new(1.1, 1.0, 2.6), CFrame.new(0, 0.75, 0.15), white)
	piece("Stripe", Enum.PartType.Block, Vector3.new(1.14, 0.18, 2.4), CFrame.new(0, 0.95, 0.15), teal, Enum.Material.Neon)
	piece("Canister", Enum.PartType.Cylinder, Vector3.new(1.7, 0.95, 0.95), CFrame.new(0, 1.55, 0.45) * alongZ, teal, Enum.Material.Glass, 0.45)
	piece("Fluid", Enum.PartType.Cylinder, Vector3.new(0.05, 0.75, 0.75), CFrame.new(0, 1.55, 0.45) * alongZ, teal, Enum.Material.Neon, 0.1)
	piece("CapBack", Enum.PartType.Cylinder, Vector3.new(0.2, 1.05, 1.05), CFrame.new(0, 1.55, 1.35) * alongZ, Color3.fromRGB(55, 60, 80))
	piece("Barrel", Enum.PartType.Cylinder, Vector3.new(1.3, 0.75, 0.75), CFrame.new(0, 0.75, -1.75) * alongZ, white)
	piece("Mouth", Enum.PartType.Cylinder, Vector3.new(0.5, 1.15, 1.15), CFrame.new(0, 0.75, -2.55) * alongZ, Color3.fromRGB(55, 60, 80))

	-- spinning rotor ring (client spins its weld while vacuuming)
	local rotor = Instance.new("Part")
	rotor.Name = "Rotor"
	rotor.Shape = Enum.PartType.Cylinder
	rotor.Size = Vector3.new(0.22, 1.35, 1.35)
	rotor.Color = teal
	rotor.Material = Enum.Material.Neon
	rotor.CanCollide = false
	rotor.CanQuery = false
	rotor.CanTouch = false
	rotor.Massless = true
	rotor.CastShadow = false
	local rotorWeld = Instance.new("Weld")
	rotorWeld.Name = "RotorWeld"
	rotorWeld.Part0 = handle
	rotorWeld.Part1 = rotor
	rotorWeld.C0 = CFrame.new(0, 0.75, -2.2) * alongZ
	rotorWeld.Parent = rotor
	rotor.Parent = tool

	-- invisible marker at the mouth for FX + server nozzle position
	local nozzle = piece("Nozzle", Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0.75, -2.85), teal, nil, 1)
	local att = Instance.new("Attachment")
	att.Name = "Mouth"
	att.Parent = nozzle

	return tool
end

local function buildJetpack(char: Model)
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	if not torso or char:FindFirstChild("Jetpack") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Jetpack"
	for _, side in { -1, 1 } do
		local p = Instance.new("Part")
		p.Name = "Thruster"
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(1.4, 0.7, 0.7)
		p.Color = Color3.fromRGB(240, 244, 250)
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = torso.CFrame * CFrame.new(side * 0.45, 0, 0.7) * CFrame.Angles(0, 0, math.pi / 2)
		local att = Instance.new("Attachment")
		att.Name = "Flame"
		att.Position = Vector3.new(-0.75, 0, 0) -- bottom end: the part is rotated so its local -X points down
		att.Parent = p
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = p
		w.Parent = p
		p.Parent = model
	end
	model.Parent = char
end

function VacService.refreshJetpack(player: Player)
	local d = DataService.get(player)
	local char = player.Character
	if d and char and Config.VacUpgrades.Jetpack.Values[d.Vac.Jetpack] > 0 then
		buildJetpack(char)
	end
end

function VacService.addPlayer(player: Player)
	states[player] = {
		On = false,
		Dir = Vector3.new(0, 0, -1),
		AimWindowStart = 0,
		AimCount = 0,
		LastShot = 0,
		LastAbsorb = 0,
		LastJet = 0,
		FullWarnAt = 0,
	}
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 10)
		VacService.refreshJetpack(player)
	end)
	if player.Character then
		VacService.refreshJetpack(player)
	end
end

function VacService.removePlayer(player: Player)
	states[player] = nil
end

function VacService.init()
	local tool = buildTool()
	tool.Parent = StarterPack
	for _, player in Players:GetPlayers() do
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack and not backpack:FindFirstChild(V.ToolName) then
			tool:Clone().Parent = backpack
		end
	end

	Remotes.event("VacInput").OnServerEvent:Connect(function(player, action, a1)
		onInput(player, action, a1)
	end)

	Remotes.event("Jet").OnServerEvent:Connect(function(player, on)
		local st = states[player]
		if not st or typeof(on) ~= "boolean" then
			return
		end
		-- throttle "on" spam; "off" always goes through so flames never stick
		local t = os.clock()
		if on and t - st.LastJet < 0.08 then
			return
		end
		st.LastJet = t
		local jp = player.Character and player.Character:FindFirstChild("Jetpack")
		if jp then
			jp:SetAttribute("JetOn", on)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(V.ServerTick)
			local ok, err = pcall(vacTick)
			if not ok then
				warn("[Vac] tick:", err)
			end
		end
	end)
end

return VacService
