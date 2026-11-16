--!strict
-- Edit-mode fixers for things already in the place (run from the command bar).
-- Everything is undoable with Ctrl+Z.
--
--   local F = require(game.ServerStorage.Fixers)
--   F.signs()     -- select sign models (posts + board), fixes floating boards
--   F.cracks()    -- select lava crack parts or the model(s) holding them
--   F.report()    -- select anything; prints what it would consider posts/boards/cracks
--
-- signs(): finds the posts (tall thin parts) and the board (biggest flat part)
--   in each selected model, then
--     * sets the board between the posts, in the posts' plane (so it's actually
--       attached, overlapping each post), keeping its height and thickness
--     * keeps any SurfaceGui/Decal text on the side it was facing
--     * extends each post down into the ground if it was hovering
-- cracks(): for every selected thin part
--     * finds the wall surface behind it (raycast along its thin axis)
--     * turns it flush to that surface and sinks its back 0.04 studs into it
--     * adds a round joint wherever two crack ends meet or almost meet, so
--       bends have no gaps (same colour/material as the crack)

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local Fixers = {}

local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

local function record(name: string, fn: () -> ())
	local id = ChangeHistoryService:TryBeginRecording(name)
	local ok, err = pcall(fn)
	if id then
		ChangeHistoryService:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	if not ok then
		warn(`[Fixers] {name} failed: {err}`)
	end
end

local function partsIn(inst: Instance): { BasePart }
	local out = {}
	if inst:IsA("BasePart") then
		table.insert(out, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- world direction of a part's local axis i (1=X, 2=Y, 3=Z)
local function axisWorld(p: BasePart, i: number): Vector3
	return p.CFrame:VectorToWorldSpace(AXES[i])
end

local function sizeOn(p: BasePart, i: number): number
	return if i == 1 then p.Size.X elseif i == 2 then p.Size.Y else p.Size.Z
end

local function thinAxis(p: BasePart): number
	local s = p.Size
	if s.X <= s.Y and s.X <= s.Z then
		return 1
	elseif s.Y <= s.Z then
		return 2
	end
	return 3
end

local function longAxis(p: BasePart): number
	local s = p.Size
	if s.X >= s.Y and s.X >= s.Z then
		return 1
	elseif s.Y >= s.Z then
		return 2
	end
	return 3
end

local NORMAL_IDS = {
	{ Enum.NormalId.Right, Vector3.new(1, 0, 0) },
	{ Enum.NormalId.Left, Vector3.new(-1, 0, 0) },
	{ Enum.NormalId.Top, Vector3.new(0, 1, 0) },
	{ Enum.NormalId.Bottom, Vector3.new(0, -1, 0) },
	{ Enum.NormalId.Back, Vector3.new(0, 0, 1) },
	{ Enum.NormalId.Front, Vector3.new(0, 0, -1) },
}

local function faceWorldNormal(cf: CFrame, face: Enum.NormalId): Vector3
	for _, pair in NORMAL_IDS do
		if pair[1] == face then
			return cf:VectorToWorldSpace(pair[2])
		end
	end
	return cf.LookVector
end

local function closestFace(cf: CFrame, worldNormal: Vector3): Enum.NormalId
	local best, bestDot = Enum.NormalId.Front, -2
	for _, pair in NORMAL_IDS do
		local d = cf:VectorToWorldSpace(pair[2]):Dot(worldNormal)
		if d > bestDot then
			best, bestDot = pair[1], d
		end
	end
	return best
end

----------------------------------------------------------------------
-- signs
----------------------------------------------------------------------
local function classifySign(model: Instance): ({ BasePart }, BasePart?)
	local posts, others = {}, {}
	for _, p in partsIn(model) do
		local s = p.Size
		local vertical = math.abs(axisWorld(p, longAxis(p)).Y)
		local long = math.max(s.X, s.Y, s.Z)
		local others2 = (s.X + s.Y + s.Z - long) / 2
		if vertical > 0.9 and long > others2 * 2.2 then
			table.insert(posts, p)
		else
			table.insert(others, p)
		end
	end
	local board: BasePart? = nil
	local bestArea = 0
	for _, p in others do
		local s = p.Size
		local t = math.min(s.X, s.Y, s.Z)
		local area = s.X * s.Y * s.Z / t
		if area > bestArea then
			board, bestArea = p, area
		end
	end
	table.sort(posts, function(a, b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)
	return posts, board
end

local function groundBelow(p: BasePart, ignore: Instance): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local bottom = p.Position - Vector3.new(0, p.Size.Y / 2, 0)
	local hit = workspace:Raycast(bottom + Vector3.new(0, 0.5, 0), Vector3.new(0, -60, 0), params)
	return hit and hit.Position.Y
end

local function fixSign(model: Instance): string
	local posts, board = classifySign(model)
	if not board then
		return "no board found"
	end
	local notes = {}

	-- posts reach the ground (sink 0.5 in)
	for _, post in posts do
		local g = groundBelow(post, model)
		local bottom = post.Position.Y - post.Size.Y / 2
		if g and bottom - g > 0.02 then
			local add = bottom - g + 0.5
			local la = longAxis(post)
			-- Size grows evenly about the centre, so drop the centre by half the growth
			post.Size += Vector3.new(if la == 1 then add else 0, if la == 2 then add else 0, if la == 3 then add else 0)
			post.CFrame = post.CFrame - Vector3.new(0, add / 2, 0)
			table.insert(notes, `post grounded (+{string.format("%.2f", add)})`)
		end
	end

	if #posts < 2 then
		return if #posts == 1 then "only one post; board left alone. " .. table.concat(notes, ", ") else "no posts found"
	end

	-- remember which way the text was facing
	local guis = {}
	for _, d in board:GetChildren() do
		if d:IsA("SurfaceGui") or d:IsA("Decal") or d:IsA("Texture") then
			table.insert(guis, { Inst = d, Normal = faceWorldNormal(board.CFrame, (d :: any).Face) })
		end
	end
	local oldFront = board.CFrame:VectorToWorldSpace(AXES[thinAxis(board)])

	local a, b = posts[1].Position, posts[2].Position
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local span = flat.Magnitude
	local right = flat.Unit
	local normal = right:Cross(Vector3.yAxis)
	if normal:Dot(oldFront) < 0 then
		right, normal = -right, -normal
	end
	local s = board.Size
	local thick = math.min(s.X, s.Y, s.Z)
	local dims = { s.X, s.Y, s.Z }
	table.sort(dims)
	local height = dims[2] -- middle dimension = board height
	-- width reaches each post's centre so the board overlaps both posts
	local width = span
	local postTop = math.min(a.Y + posts[1].Size.Y / 2, b.Y + posts[2].Size.Y / 2)
	local centerY = math.min(board.Position.Y, postTop - 0.3 - height / 2)
	local mid = (a + b) / 2
	local center = Vector3.new(mid.X, centerY, mid.Z)
	board.Size = Vector3.new(width, height, thick)
	board.CFrame = CFrame.fromMatrix(center, right, Vector3.yAxis) -- Z = right x up
	for _, g in guis do
		(g.Inst :: any).Face = closestFace(board.CFrame, g.Normal)
	end
	table.insert(notes, "board set between posts")
	return table.concat(notes, ", ")
end

function Fixers.signs()
	local sel = Selection:Get()
	assert(#sel > 0, "Select sign models first")
	record("Fix signs", function()
		for _, m in sel do
			print(`[Fixers] {m:GetFullName()}: {fixSign(m)}`)
		end
	end)
end

----------------------------------------------------------------------
-- cracks
----------------------------------------------------------------------
local function flushToSurface(p: BasePart, ignore: { Instance }): boolean
	local ti = thinAxis(p)
	local axis = axisWorld(p, ti)
	local thick = sizeOn(p, ti)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local best: RaycastResult? = nil
	for _, dir in { axis, -axis } do
		local hit = workspace:Raycast(p.Position - dir * 0.5, dir * 6, params)
		if hit and math.abs(hit.Normal:Dot(axis)) > 0.6 and (not best or hit.Distance < best.Distance) then
			best = hit
		end
	end
	if not best then
		return false
	end
	local n = best.Normal
	-- rotate so the thin axis lines up with the surface normal (smallest rotation)
	local from = if axis:Dot(n) >= 0 then axis else -axis
	local rotAxis = from:Cross(n)
	local rot = CFrame.new()
	if rotAxis.Magnitude > 1e-4 then
		local angle = math.acos(math.clamp(from:Dot(n), -1, 1))
		rot = CFrame.fromAxisAngle(rotAxis.Unit, angle)
	end
	local c = p.Position
	local onPlane = c - n * (c - best.Position):Dot(n)
	local newPos = onPlane + n * (thick / 2 - 0.04) -- back face 0.04 inside the wall
	p.CFrame = CFrame.new(newPos) * rot * (p.CFrame - p.Position)
	return true
end

local function endpoints(p: BasePart): (Vector3, Vector3, number)
	local la = longAxis(p)
	local dir = axisWorld(p, la)
	local half = sizeOn(p, la) / 2
	local s = p.Size
	local dims = { s.X, s.Y, s.Z }
	table.sort(dims)
	return p.Position + dir * half, p.Position - dir * half, dims[2]
end

function Fixers.cracks()
	local sel = Selection:Get()
	assert(#sel > 0, "Select crack parts (or the model holding them) first")
	record("Fix cracks", function()
		local cracks: { BasePart } = {}
		for _, s in sel do
			for _, p in partsIn(s) do
				if p.Name ~= "CrackJoint" then
					table.insert(cracks, p)
				end
			end
		end
		local ignore: { Instance } = {}
		for _, c in cracks do
			table.insert(ignore, c)
		end
		local flushed, missed = 0, 0
		for _, c in cracks do
			if flushToSurface(c, ignore) then
				flushed += 1
			else
				missed += 1
			end
		end
		-- join ends that meet or nearly meet
		type End = { Pos: Vector3, Part: BasePart, Width: number, Used: boolean }
		local ends: { End } = {}
		for _, c in cracks do
			local e1, e2, w = endpoints(c)
			table.insert(ends, { Pos = e1, Part = c, Width = w, Used = false })
			table.insert(ends, { Pos = e2, Part = c, Width = w, Used = false })
		end
		local joints = 0
		for i, e in ends do
			if e.Used then
				continue
			end
			local group = { e }
			for j = i + 1, #ends do
				local o = ends[j]
				if not o.Used and o.Part ~= e.Part and (o.Pos - e.Pos).Magnitude < 1.2 then
					table.insert(group, o)
				end
			end
			if #group < 2 then
				continue
			end
			local centre, maxW, maxGap = Vector3.zero, 0, 0
			for _, g in group do
				g.Used = true
				centre += g.Pos
				maxW = math.max(maxW, g.Width)
			end
			centre /= #group
			for _, g in group do
				maxGap = math.max(maxGap, (g.Pos - centre).Magnitude)
			end
			local host = e.Part
			local ti = thinAxis(host)
			local n = axisWorld(host, ti)
			-- 0.06 thicker than the strip and centred on it: 0.03 proud on the front,
			-- deeper in the wall at the back, so never coplanar with the strips
			local thick = sizeOn(host, ti) + 0.06
			local d = maxW + maxGap * 2 -- big enough to cover any gap between the ends
			local joint = Instance.new("Part")
			joint.Name = "CrackJoint"
			joint.Shape = Enum.PartType.Cylinder
			joint.Anchored = true
			joint.CanCollide = false
			joint.CanQuery = false
			joint.CanTouch = false
			joint.CastShadow = false
			joint.Material = host.Material
			joint.Color = host.Color
			joint.Size = Vector3.new(thick, d, d)
			-- cylinder axis (X) along the surface normal
			joint.CFrame = CFrame.lookAt(centre, centre + n) * CFrame.Angles(0, math.pi / 2, 0)
			joint.Parent = host.Parent
			joints += 1
		end
		print(`[Fixers] cracks: {flushed} made flush, {missed} had no wall behind them, {joints} joints added`)
	end)
end

function Fixers.report()
	for _, s in Selection:Get() do
		local posts, board = classifySign(s)
		print(`[Fixers] {s:GetFullName()}: {#posts} post(s), board = {if board then board:GetFullName() else "none"}`)
	end
end

return Fixers
