--!strict
-- Edit-mode wall builder for the Beach and Volcano worlds (run from the Studio
-- command bar; it is NOT a runtime script).
--
-- How to use:
--   1. Put this ModuleScript in ServerStorage (named WallKit).
--   2. Drop a plain Part where a wall should go. Stretch it along its X axis to
--      the wall length. Its FRONT face (the one the Move tool's blue/-Z arrow
--      points out of) must face the play area. Its bottom is the ground line.
--   3. Select one or more of those guide parts and run in the command bar:
--        require(game.ServerStorage.WallKit).fromSelection("Beach")
--        require(game.ServerStorage.WallKit).fromSelection("Volcano")
--      The guides are replaced by walls (Ctrl+Z undoes it). Same guide + same
--      Seed attribute = same wall, so you can rebuild after tweaking.
--
-- Rules the builder follows so it doesn't look cheap:
--   * no two faces coplanar (neighbouring heights/depths always differ by
--     >= 0.6 studs, caps overhang blocks, details sit proud or recessed) -> no z-fighting
--   * every detail is embedded into something solid -> nothing floats
--   * lava cracks are continuous: every bend gets a joint ball the same width
--     as the strip, so there are no gaps at corners
--   * decor is non-collide, non-query, mostly shadowless; walls are anchored (mobile)

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local WallKit = {}

type Ctx = { Model: Model, Rng: Random, CF: CFrame, Length: number }

----------------------------------------------------------------------
-- part helpers
----------------------------------------------------------------------
local function part(ctx: Ctx, class: string, props: { [string]: any }, decor: boolean?): BasePart
	local p = Instance.new(class) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if decor then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	else
		p.CanTouch = false
	end
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = ctx.Model
	return p
end

-- local wall space: X along the wall, Y up, +Z = depth INTO the wall (front line at z = 0)
local function L(ctx: Ctx, x: number, y: number, z: number): CFrame
	return ctx.CF * CFrame.new(x, y, z)
end

local function jitterColor(rng: Random, c: Color3, amount: number): Color3
	local d = rng:NextNumber(-amount, amount)
	return Color3.new(math.clamp(c.R + d, 0, 1), math.clamp(c.G + d, 0, 1), math.clamp(c.B + d, 0, 1))
end

-- split the wall length into blocks of random width
local function spans(rng: Random, length: number, minW: number, maxW: number): { { number } }
	-- (callers pass a slightly different length per tier so wall ends never line up)
	local out = {}
	local x = -length / 2
	while x < length / 2 - 0.01 do
		local w = math.min(math.floor(rng:NextNumber(minW, maxW) * 2 + 0.5) / 2, length / 2 - x)
		if length / 2 - (x + w) < minW * 0.5 then
			w = length / 2 - x -- don't leave a sliver at the end
		end
		table.insert(out, { x, w })
		x += w
	end
	return out
end

-- pick a value that differs from the previous one by at least gap
local function distinct(rng: Random, lo: number, hi: number, prev: number?, gap: number): number
	for _ = 1, 12 do
		local v = rng:NextNumber(lo, hi)
		if not prev or math.abs(v - prev) >= gap then
			return v
		end
	end
	return (prev or lo) + gap
end

-- Cliff heights, widths and depths live on a 0.5-stud grid. Every other kind of
-- face (cap tops/bottoms/fronts/sides, crust, chamfers, ledges) sits at its own
-- fixed offset that is never a multiple of 0.5, so two different parts can never
-- end up in the same plane by chance. Keep that in mind when tweaking numbers.
local function snap(h: number): number
	return math.floor(h * 2 + 0.5) / 2
end

----------------------------------------------------------------------
-- shared decor
----------------------------------------------------------------------
local function rock(ctx: Ctx, cf: CFrame, size: number, color: Color3)
	local r = ctx.Rng
	-- two rotated blocks read as a chunky low-poly boulder
	part(ctx, "Part", { Name = "Rock", Size = Vector3.new(size * 1.3, size * 0.8, size), CFrame = cf * CFrame.new(0, size * 0.3, 0) * CFrame.Angles(r:NextNumber(-0.3, 0.3), r:NextNumber(0, 6), r:NextNumber(-0.25, 0.25)), Color = color }, true)
	part(ctx, "Part", { Name = "Rock", Size = Vector3.new(size * 0.9, size * 0.7, size * 0.9), CFrame = cf * CFrame.new(size * 0.15, size * 0.45, 0) * CFrame.Angles(r:NextNumber(-0.5, 0.5), r:NextNumber(0, 6), r:NextNumber(-0.5, 0.5)), Color = jitterColor(r, color, 0.04) }, true)
end

local function crystals(ctx: Ctx, cf: CFrame, color: Color3, scale: number, neon: boolean?)
	local r = ctx.Rng
	for _ = 1, r:NextInteger(3, 5) do
		local h = r:NextNumber(1.4, 3) * scale
		local w = r:NextNumber(0.45, 0.7) * scale
		local tilt = CFrame.Angles(r:NextNumber(-0.45, 0.45), r:NextNumber(0, 6), r:NextNumber(-0.45, 0.45))
		local base = cf * CFrame.new(r:NextNumber(-0.5, 0.5) * scale, 0, r:NextNumber(-0.5, 0.5) * scale) * tilt
		part(ctx, "Part", { Name = "Crystal", Size = Vector3.new(w, h, w), CFrame = base * CFrame.new(0, h / 2 - 0.2, 0), Color = jitterColor(r, color, 0.05), Material = if neon then Enum.Material.Neon else Enum.Material.Glass, Transparency = if neon then 0 else 0.12 }, true)
		-- pointed tip
		part(ctx, "WedgePart", { Name = "CrystalTip", Size = Vector3.new(w, w * 1.1, w), CFrame = base * CFrame.new(0, h - 0.2 + w * 0.55 - 0.01, 0), Color = jitterColor(r, color, 0.05), Material = if neon then Enum.Material.Neon else Enum.Material.Glass, Transparency = if neon then 0 else 0.12 }, true)
	end
end

local function tuft(ctx: Ctx, cf: CFrame, color: Color3, scale: number)
	local r = ctx.Rng
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2
		part(ctx, "Part", { Name = "Grass", Size = Vector3.new(0.18, r:NextNumber(0.9, 1.6) * scale, 0.5 * scale), CFrame = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.5 * scale, 0.15) * CFrame.Angles(r:NextNumber(0.2, 0.5), 0, 0), Color = jitterColor(r, color, 0.05) }, true)
	end
end

local function flower(ctx: Ctx, cf: CFrame)
	part(ctx, "Part", { Name = "Stem", Size = Vector3.new(0.15, 0.8, 0.15), CFrame = cf * CFrame.new(0, 0.4, 0), Color = Color3.fromRGB(80, 170, 60) }, true)
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2
		part(ctx, "Part", { Name = "Petal", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), CFrame = cf * CFrame.new(math.cos(a) * 0.32, 0.85, math.sin(a) * 0.32), Color = Color3.fromRGB(235, 45, 50) }, true)
	end
	part(ctx, "Part", { Name = "Center", Shape = Enum.PartType.Ball, Size = Vector3.new(0.38, 0.38, 0.38), CFrame = cf * CFrame.new(0, 0.9, 0), Color = Color3.fromRGB(255, 210, 60) }, true)
end

local function palm(ctx: Ctx, cf: CFrame, height: number)
	local r = ctx.Rng
	local lean = r:NextNumber(0.08, 0.16)
	local dir = r:NextNumber(0, math.pi * 2)
	local at = cf * CFrame.Angles(0, dir, 0)
	local segs = 7
	local segLen = height / segs
	for i = 1, segs do
		-- curve: each segment leans a bit more than the last
		at = at * CFrame.Angles(0, 0, lean * (0.4 + i / segs))
		local w = 1.0 - i * 0.05
		part(ctx, "Part", { Name = "Trunk", Size = Vector3.new(w, segLen + 0.12, w), CFrame = at * CFrame.new(0, segLen / 2, 0), Color = if i % 2 == 0 then Color3.fromRGB(176, 110, 60) else Color3.fromRGB(160, 98, 52) }, true)
		at = at * CFrame.new(0, segLen, 0)
	end
	local top = at
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2 + r:NextNumber(-0.15, 0.15)
		-- fronds radiate out and droop: negative X rotation tips -Z downward
		local frond = top * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-r:NextNumber(5, 20)), 0, 0)
		local len = r:NextNumber(4, 5.5)
		part(ctx, "Part", { Name = "Frond", Size = Vector3.new(1.6, 0.18, len * 0.6), CFrame = frond * CFrame.new(0, 0, -len * 0.3), Color = Color3.fromRGB(120, 210, 55) }, true)
		part(ctx, "Part", { Name = "FrondTip", Size = Vector3.new(1.2, 0.18, len * 0.45), CFrame = frond * CFrame.new(0, 0, -len * 0.6 + 0.1) * CFrame.Angles(math.rad(-35), 0, 0) * CFrame.new(0, 0, -len * 0.22), Color = Color3.fromRGB(105, 195, 50) }, true)
	end
end

local function blockyTree(ctx: Ctx, cf: CFrame, color: Color3)
	local r = ctx.Rng
	local h = r:NextNumber(3, 4.5)
	part(ctx, "Part", { Name = "Trunk", Size = Vector3.new(0.7, h, 0.7), CFrame = cf * CFrame.new(0, h / 2, 0), Color = Color3.fromRGB(120, 80, 60) }, true)
	for _ = 1, 3 do
		local s = r:NextNumber(2, 3)
		part(ctx, "Part", { Name = "Leaves", Size = Vector3.new(s, s * 0.8, s), CFrame = cf * CFrame.new(r:NextNumber(-1, 1), h + r:NextNumber(-0.2, 1.2), r:NextNumber(-1, 1)) * CFrame.Angles(0, r:NextNumber(0, 6), 0), Color = jitterColor(r, color, 0.05) }, true)
	end
end

----------------------------------------------------------------------
-- BEACH: stepped pastel cliffs, pink frosting caps with drips, grass
-- ledges with hanging square vines, palms, crystals, banners
----------------------------------------------------------------------
local SAND = Color3.fromRGB(248, 205, 188)
local FROST = Color3.fromRGB(244, 140, 205)
local GRASS = Color3.fromRGB(125, 222, 58)
local ROCK = Color3.fromRGB(150, 138, 176)

local function frostCap(ctx: Ctx, x: number, w: number, top: number, z0: number, depth: number, grass: boolean)
	local r = ctx.Rng
	local col = if grass then GRASS else FROST
	local front = z0 - 0.6 -- cap overhangs the block front by 0.6
	part(ctx, "Part", { Name = if grass then "GrassCap" else "FrostCap", Size = Vector3.new(w + 1.2, 1.3, depth + 1.2), CFrame = L(ctx, x + w / 2, top + 0.6, z0 + depth / 2), Color = col }) -- bottom 0.05 inside the block
	-- notches / drips hanging off the front edge, recessed 0.12 behind the cap face
	local cx = x + 0.2
	while cx < x + w - 1.6 do -- stay inside this block's width
		local dw = r:NextNumber(0.8, 1.4)
		local dh = if grass then r:NextNumber(0.6, 1.0) else r:NextNumber(0.7, 2.0)
		part(ctx, "Part", { Name = "Drip", Size = Vector3.new(dw, dh, 0.7), CFrame = L(ctx, cx + dw / 2, top - dh / 2 + 0.05, front + 0.12 + 0.35), Color = jitterColor(r, col, 0.03) }, true)
		cx += dw + r:NextNumber(1.1, 2.4)
	end
	if grass then
		-- hanging square-leaf vines
		local used: { number } = {}
		for _ = 1, r:NextInteger(1, math.max(1, math.floor(w / 4))) do
			local vx = x + r:NextNumber(0.8, w - 0.8)
			local clash = false
			for _, u in used do
				if math.abs(u - vx) < 1.6 then
					clash = true -- chains this close would overlap leaf-on-leaf
				end
			end
			if clash then
				continue
			end
			table.insert(used, vx)
			local n = r:NextInteger(3, 6)
			for i = 1, n do
				local side = if i % 2 == 0 then 0.18 else -0.18
				-- first leaf tucks into the cap, each next one overlaps the last,
				-- and the back of every leaf sits 0.03 inside the cliff face
				-- alternate leaf thickness (0.25 / 0.34) with a shared back plane, so the
				-- overlapping leaves never have coplanar front faces
				local th = if i % 2 == 0 then 0.34 else 0.25
				part(ctx, "Part", { Name = "Vine", Size = Vector3.new(0.7, 0.7, th), CFrame = L(ctx, vx + side, top - 0.3 - (i - 1) * 0.62, z0 + 0.03 - th / 2) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 8 else -8)), Color = jitterColor(r, Color3.fromRGB(95, 190, 60), 0.04) }, true)
			end
		end
		-- tufts on the grass top
		for _ = 1, math.floor(w / 8) do
			tuft(ctx, L(ctx, x + r:NextNumber(0.5, w - 0.5), top + 1.3, z0 + r:NextNumber(0.3, 1.5)), Color3.fromRGB(170, 230, 80), 1)
		end
	end
end

local function beachTier(ctx: Ctx, z0: number, depth: number, hLo: number, hHi: number, grassChance: number, minW: number, maxW: number, extra: number): { { number } }
	local r = ctx.Rng
	local tops = {}
	local prevH: number? = nil
	local prevZ: number? = nil
	for _, sp in spans(r, ctx.Length + extra, minW, maxW) do
		local x, w = sp[1], sp[2]
		local h = snap(distinct(r, hLo, hHi, prevH, 1.0))
		local z = z0 + snap(distinct(r, -1.2, 1.2, if prevZ then prevZ - z0 else nil, 0.6))
		if prevZ and math.abs(z - prevZ) < 0.5 then
			z = prevZ + (if z >= prevZ then 0.5 else -0.5)
		end
		prevH, prevZ = h, z
		-- extend each block a bit into its neighbours so seams are hidden; differing
		-- front depth + height keeps the overlapping faces from being coplanar
		part(ctx, "Part", { Name = "Cliff", Size = Vector3.new(w + 0.6, h + 4, depth), CFrame = L(ctx, x + w / 2, (h - 4) / 2, z + depth / 2), Color = jitterColor(r, SAND, 0.025) }) -- 4 studs below ground: never floats on uneven terrain
		frostCap(ctx, x, w, h, z, depth, r:NextNumber() < grassChance)
		table.insert(tops, { x, w, h, z })
	end
	return tops
end

local function buildBeach(ctx: Ctx)
	local r = ctx.Rng
	local t1 = beachTier(ctx, 0, 9, 9, 13, 0.65, 9, 16, 0)
	local t2 = beachTier(ctx, 7, 10, 18, 24, 0.45, 10, 18, 1.4)
	local t3 = beachTier(ctx, 15, 12, 28, 35, 0.25, 12, 20, 2.8)
	-- props on ledges: palms, crystals, rocks, flowers (each sits on a cap top)
	for _, tier in { t1, t2, t3 } do
		for _, b in tier do
			local x, w, h, z = b[1], b[2], b[3], b[4]
			local topY = h + 1.3
			local roll = r:NextNumber()
			local px = x + r:NextNumber(1.5, math.max(1.6, w - 1.5))
			if roll < 0.18 then
				palm(ctx, L(ctx, px, topY - 0.2, z + 3), r:NextNumber(7, 10))
			elseif roll < 0.33 then
				crystals(ctx, L(ctx, px, topY, z + 1.6), if r:NextNumber() < 0.5 then Color3.fromRGB(255, 120, 220) else Color3.fromRGB(130, 170, 255), 1)
			elseif roll < 0.5 then
				rock(ctx, L(ctx, px, topY - 0.3, z + 2), r:NextNumber(1.6, 2.6), ROCK)
			end
			if r:NextNumber() < 0.25 then
				flower(ctx, L(ctx, x + r:NextNumber(1, math.max(1.1, w - 1)), topY, z + 1.2))
			end
		end
	end
	-- banners on the bottom tier faces (sit 0.15 proud of the cliff face)
	for _, b in t1 do
		if r:NextNumber() < 0.22 then
			local x, w, h, z = b[1], b[2], b[3], b[4]
			local bx, by = x + w / 2, h * 0.55
			-- rod's back face 0.005 inside the cliff; banner hangs from the rod
			part(ctx, "Part", { Name = "BannerRod", Size = Vector3.new(2.8, 0.25, 0.25), CFrame = L(ctx, bx, by + 2.2, z - 0.12), Color = Color3.fromRGB(130, 85, 55) }, true)
			local banner = part(ctx, "Part", { Name = "Banner", Size = Vector3.new(2, 3.4, 0.12), CFrame = L(ctx, bx, by + 0.4, z - 0.2), Color = Color3.fromRGB(60, 170, 250) }, true)
			-- emblem disc: back embedded in the banner, front 0.05 proud of it
			part(ctx, "Part", { Name = "BannerEmblem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.1, 1.1), CFrame = banner.CFrame * CFrame.new(0, 0.2, -0.05) * CFrame.Angles(0, math.pi / 2, 0), Color = Color3.fromRGB(235, 250, 255) }, true)
		end
	end
	-- ground dressing in front: rocks, crystals, starfish, palms
	for _ = 1, math.floor(ctx.Length / 7) do
		local gx = r:NextNumber(-ctx.Length / 2 + 1, ctx.Length / 2 - 1)
		local roll = r:NextNumber()
		if roll < 0.35 then
			rock(ctx, L(ctx, gx, -0.2, r:NextNumber(-2.5, -1)), r:NextNumber(1.5, 2.8), ROCK)
		elseif roll < 0.5 then
			crystals(ctx, L(ctx, gx, 0, -1.2), Color3.fromRGB(110, 225, 255), 0.8)
		elseif roll < 0.7 then
			-- starfish: five flat arms
			local c = L(ctx, gx, 0.08, r:NextNumber(-8, -3)) * CFrame.Angles(0, r:NextNumber(0, 6), 0)
			for k = 0, 4 do
				part(ctx, "Part", { Name = "Starfish", Size = Vector3.new(0.35, 0.12, 0.6), CFrame = c * CFrame.Angles(0, k * math.pi * 2 / 5, 0) * CFrame.new(0, 0, -0.62), Color = Color3.fromRGB(240, 120, 60) }, true)
			end
			-- taller centre hides where the arms overlap (no coplanar tops)
			part(ctx, "Part", { Name = "StarfishCenter", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 0.8, 0.8), CFrame = c * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(240, 120, 60) }, true)
		elseif roll < 0.8 then
			palm(ctx, L(ctx, gx, 0, r:NextNumber(-6, -3)), r:NextNumber(6, 8))
		else
			tuft(ctx, L(ctx, gx, 0, -0.8), Color3.fromRGB(150, 225, 80), 1.1)
		end
	end
end

----------------------------------------------------------------------
-- VOLCANO: dark faceted cliffs, orange lava-crust caps and ledges,
-- branching glowing cracks, lavafalls with pools, orange crystals
----------------------------------------------------------------------
local BASALT = Color3.fromRGB(98, 84, 116)
local CRUST = Color3.fromRGB(255, 118, 28)
local CRUST_UNDER = Color3.fromRGB(205, 78, 32)
local LAVA = Color3.fromRGB(255, 150, 40)

-- a crack is a polyline on the face plane at depth z (face) running in X/Y
local crackCount = 0
local function crack(ctx: Ctx, faceZ: number, x0: number, y0: number, xMin: number, xMax: number, yMax: number, depth: number)
	local r = ctx.Rng
	-- every strip/joint on a face gets its own thickness (counter resets per
	-- block), so no two overlapping crack pieces ever share a front plane
	local function nextThickness(): number
		crackCount += 1
		return 0.22 + (crackCount % 24) * 0.005
	end
	local width = r:NextNumber(0.38, 0.55)
	-- every piece shares one back plane 0.04 inside the rock
	local function zFor(th: number): number
		return faceZ + 0.04 - th / 2
	end
	local pts = { Vector2.new(x0, y0) }
	local p = pts[1]
	local heading = math.rad(r:NextNumber(60, 120))
	for _ = 1, r:NextInteger(4, 7) do
		heading += math.rad(r:NextNumber(-45, 45))
		local len = r:NextNumber(1.2, 2.6)
		local q = p + Vector2.new(math.cos(heading), math.sin(heading)) * len
		if q.X < xMin or q.X > xMax or q.Y < 0.5 or q.Y > yMax then
			break -- end at the edge rather than sliding along it
		end
		-- stop instead of doubling back over itself (overlapping strips look messy)
		local loops = false
		for k = 1, #pts - 1 do
			if (pts[k] - q).Magnitude < width * 2 then
				loops = true
			end
		end
		if loops then
			break
		end
		table.insert(pts, q)
		p = q
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local mid = (a + b) / 2
		local d = b - a
		local ang = math.atan2(d.Y, d.X)
		local th = nextThickness()
		part(ctx, "Part", { Name = "Crack", Size = Vector3.new(d.Magnitude, width, th), CFrame = L(ctx, mid.X, mid.Y, zFor(th)) * CFrame.Angles(0, 0, ang), Color = LAVA, Material = Enum.Material.Neon }, true)
	end
	-- round joint at every vertex, same width and depth as the strips: no gaps
	-- or bumps at bends (cylinder axis turned to face out of the wall)
	for i = 1, #pts do
		local q = pts[i]
		local th = nextThickness()
		part(ctx, "Part", { Name = "CrackJoint", Shape = Enum.PartType.Cylinder, Size = Vector3.new(th, width, width), CFrame = L(ctx, q.X, q.Y, zFor(th)) * CFrame.Angles(0, math.pi / 2, 0), Color = LAVA, Material = Enum.Material.Neon }, true)
	end
	-- occasional branch off a middle vertex
	if depth < 1 and #pts > 3 then
		local k = r:NextInteger(2, #pts - 1)
		crack(ctx, faceZ, pts[k].X, pts[k].Y, xMin, xMax, yMax, depth + 1)
	end
end

local function lavaCap(ctx: Ctx, x: number, w: number, top: number, z0: number, depth: number)
	local r = ctx.Rng
	-- dark underside first, crust on top, both overhanging the rock
	part(ctx, "Part", { Name = "CrustUnder", Size = Vector3.new(w + 0.8, 0.6, depth + 0.8), CFrame = L(ctx, x + w / 2, top + 0.25, z0 + depth / 2), Color = CRUST_UNDER })
	-- big overhang like the reference's thick lava-crust slabs
	part(ctx, "Part", { Name = "Crust", Size = Vector3.new(w + 2.46, 1.63, depth + 3.2), CFrame = L(ctx, x + w / 2, top + 0.5 + 0.815, z0 + depth / 2 - 0.47), Color = jitterColor(r, CRUST, 0.02) })
	-- lumpy edge: a couple of extra slabs at slightly different heights
	for k = 1, r:NextInteger(1, 2) do
		local lw = r:NextNumber(2, math.max(2.1, w * 0.5))
		local lx = x + r:NextNumber(0, math.max(0.1, w - lw))
		-- second lump is deeper and taller than the first: no shared planes
		part(ctx, "Part", { Name = "CrustLump", Size = Vector3.new(lw, 0.7 + k * 0.15, 2.2 + k * 0.4), CFrame = L(ctx, lx + lw / 2, top + 2.0 + k * 0.12, z0 + 0.9 + k * 0.35), Color = jitterColor(r, CRUST, 0.03) }, true)
	end
end

local function volcanoTier(ctx: Ctx, z0: number, depth: number, hLo: number, hHi: number, minW: number, maxW: number, extra: number): { { number } }
	local r = ctx.Rng
	local out = {}
	local prevH: number? = nil
	local prevZ: number? = nil
	local prevFacetDeep = false
	for _, sp in spans(r, ctx.Length + extra, minW, maxW) do
		local x, w = sp[1], sp[2]
		local h = snap(distinct(r, hLo, hHi, prevH, 1.2))
		local z = z0 + snap(distinct(r, -1.4, 1.4, if prevZ then prevZ - z0 else nil, 0.6))
		if prevZ and math.abs(z - prevZ) < 0.5 then
			z = prevZ + (if z >= prevZ then 0.5 else -0.5)
		end
		prevH, prevZ = h, z
		local col = jitterColor(r, BASALT, 0.03)
		part(ctx, "Part", { Name = "Cliff", Size = Vector3.new(w + 0.6, h + 4, depth), CFrame = L(ctx, x + w / 2, (h - 4) / 2, z + depth / 2), Color = col })
		-- faceted front: a chamfer wedge along the top front edge
		-- neighbours alternate chamfer depth so their slopes are never parallel
		local fd = if prevFacetDeep then 1.6 else 1.85
		prevFacetDeep = not prevFacetDeep
		part(ctx, "WedgePart", { Name = "Facet", Size = Vector3.new(w + 0.46, 1.6, fd), CFrame = L(ctx, x + w / 2, h - 0.8, z + 0.25 - fd / 2) * CFrame.Angles(0, math.pi, 0), Color = jitterColor(r, col, 0.03) }, true)
		lavaCap(ctx, x, w, h, z, depth)
		-- angular rock facet leaning out of the face (embedded, gives the
		-- diagonal planes the reference cliffs have)
		if h > 10 and r:NextNumber() < 0.6 then
			local fw = r:NextNumber(3, math.max(3.1, w * 0.6))
			local fh = r:NextNumber(h * 0.35, h * 0.6)
			local fx = x + r:NextNumber(fw / 2, math.max(fw / 2 + 0.1, w - fw / 2))
			part(ctx, "Part", { Name = "RockFacet", Size = Vector3.new(fw, fh, 2.4), CFrame = L(ctx, fx, snap(r:NextNumber(fh * 0.5, h - fh * 0.5 - 1)) + 0.33, z + 0.7) * CFrame.Angles(math.rad(-r:NextNumber(6, 12)), math.rad(r:NextNumber(-8, 8)), 0), Color = jitterColor(r, col, 0.035) })
		end
		-- mid-height crust ledge sticking out of some faces (embedded 1 stud)
		if h > 12 and r:NextNumber() < 0.45 then
			local lw = r:NextNumber(4, math.max(4.1, w))
			local ly = snap(r:NextNumber(h * 0.4, h * 0.7)) + 0.27
			local lx = x + r:NextNumber(0, math.max(0.1, w - lw))
			part(ctx, "Part", { Name = "LedgeUnder", Size = Vector3.new(lw, 0.6, 3.0), CFrame = L(ctx, lx + lw / 2, ly - 0.25, z - 0.7), Color = CRUST_UNDER })
			part(ctx, "Part", { Name = "Ledge", Size = Vector3.new(lw + 0.6, 1.1, 3.6), CFrame = L(ctx, lx + lw / 2, ly + 0.55, z - 1.8 + 1.0), Color = CRUST })
		end
		-- cracks on the face
		crackCount = 0
		for _ = 1, math.max(1, math.floor(w / 7)) do
			if r:NextNumber() < 0.75 then
				crack(ctx, z, x + r:NextNumber(1, math.max(1.1, w - 1)), r:NextNumber(1, h * 0.4), x + 0.4, x + w - 0.4, h - 2.2, 0)
			end
		end
		table.insert(out, { x, w, h, z })
	end
	return out
end

local function lavafall(ctx: Ctx, x: number, top: number, faceZ: number)
	local r = ctx.Rng
	local w = r:NextNumber(1.8, 2.6)
	-- sheet's back face 0.05 inside the rock; brighter core's back 0.05 inside the sheet
	part(ctx, "Part", { Name = "Lavafall", Size = Vector3.new(w, top, 0.5), CFrame = L(ctx, x, top / 2, faceZ - 0.2), Color = Color3.fromRGB(255, 120, 30), Material = Enum.Material.Neon }, true)
	part(ctx, "Part", { Name = "LavafallCore", Size = Vector3.new(w * 0.55, top - 0.2, 0.3), CFrame = L(ctx, x, (top - 0.2) / 2, faceZ - 0.55), Color = Color3.fromRGB(255, 205, 90), Material = Enum.Material.Neon, Transparency = 0.25 }, true)
	-- pool + rim at the bottom
	part(ctx, "Part", { Name = "PoolRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, w * 2.6, w * 2.6), CFrame = L(ctx, x, 0.2, faceZ - w * 1.1) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(70, 60, 80) }, true)
	local pool = part(ctx, "Part", { Name = "LavaPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, w * 2.1, w * 2.1), CFrame = L(ctx, x, 0.25, faceZ - w * 1.1) * CFrame.Angles(0, 0, math.pi / 2), Color = LAVA, Material = Enum.Material.Neon }, true)
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0.3, 0, 0)
	att.Parent = pool
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.EmissionDirection = Enum.NormalId.Right -- cylinder axis X is up here
	e.Rate = 6
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Size = NumberSequence.new(0.5, 0)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
	e.LightEmission = 1
	e.Parent = att
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 50)
	light.Range = 14
	light.Brightness = 1.5
	light.Shadows = false
	light.Parent = pool
end

local function buildVolcano(ctx: Ctx)
	local r = ctx.Rng
	local t1 = volcanoTier(ctx, 0, 10, 12, 17, 9, 15, 0)
	volcanoTier(ctx, 8, 11, 22, 29, 10, 17, 1.4)
	volcanoTier(ctx, 17, 13, 32, 40, 12, 20, 2.8)
	-- lavafalls pouring off the front tier's crust (so nothing hides them)
	for _, b in t1 do
		if r:NextNumber() < 0.22 then
			local x, w, h, z = b[1], b[2], b[3], b[4]
			lavafall(ctx, x + w / 2, h + 0.3, z)
		end
	end
	-- leaning boulders, crystals, little trees along the base
	for _, b in t1 do
		local x, w, _, z = b[1], b[2], b[3], b[4]
		if r:NextNumber() < 0.4 then
			local s = r:NextNumber(3, 6)
			part(ctx, "Part", { Name = "Boulder", Size = Vector3.new(s, s * 1.8, s * 0.9), CFrame = L(ctx, x + r:NextNumber(1, math.max(1.1, w - 1)), s * 0.8, z - s * 0.35) * CFrame.Angles(math.rad(r:NextNumber(8, 16)), r:NextNumber(-0.4, 0.4), r:NextNumber(-0.2, 0.2)), Color = jitterColor(r, Color3.fromRGB(110, 96, 128), 0.03) })
		end
	end
	for _ = 1, math.floor(ctx.Length / 8) do
		local gx = r:NextNumber(-ctx.Length / 2 + 1, ctx.Length / 2 - 1)
		local roll = r:NextNumber()
		if roll < 0.35 then
			rock(ctx, L(ctx, gx, -0.2, r:NextNumber(-3, -1)), r:NextNumber(1.6, 3), Color3.fromRGB(120, 108, 135))
		elseif roll < 0.5 then
			crystals(ctx, L(ctx, gx, 0, -1.5), Color3.fromRGB(255, 165, 50), 1.1, true)
		elseif roll < 0.65 then
			local colors = { Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 200, 50), Color3.fromRGB(240, 70, 60) }
			blockyTree(ctx, L(ctx, gx, 0, r:NextNumber(-9, -5)), colors[r:NextInteger(1, #colors)])
		end
	end
end

----------------------------------------------------------------------
function WallKit.build(kind: string, guide: BasePart): Model
	local seed = guide:GetAttribute("Seed")
	local model = Instance.new("Model")
	model.Name = `{kind}Wall`
	-- bottom-front edge of the guide is the wall's origin; local +Z = into the wall
	-- origin = bottom of the guide's front face. Local axes match the guide, so
	-- +Z runs back into the wall and -Z faces the play area.
	local ctx: Ctx = {
		Model = model,
		Rng = Random.new(if typeof(seed) == "number" then seed else math.floor(guide.Position.X * 7 + guide.Position.Z * 13)),
		CF = guide.CFrame * CFrame.new(0, -guide.Size.Y / 2, -guide.Size.Z / 2),
		Length = guide.Size.X,
	}
	if kind == "Volcano" then
		buildVolcano(ctx)
	else
		buildBeach(ctx)
	end
	return model
end

function WallKit.fromSelection(kind: string)
	assert(kind == "Beach" or kind == "Volcano", 'kind must be "Beach" or "Volcano"')
	local guides = {}
	for _, s in Selection:Get() do
		if s:IsA("BasePart") then
			table.insert(guides, s)
		end
	end
	assert(#guides > 0, "Select one or more guide parts first")
	local recording = ChangeHistoryService:TryBeginRecording(`Build {kind} walls`)
	local folder = workspace:FindFirstChild(`{kind}Walls`) or Instance.new("Folder")
	folder.Name = `{kind}Walls`
	folder.Parent = workspace
	local made = {}
	local parts = 0
	for _, g in guides do
		local m = WallKit.build(kind, g)
		m.Parent = folder
		parts += #m:GetChildren()
		table.insert(made, m)
		g.Parent = nil -- undo restores it
	end
	Selection:Set(made)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	print(`[WallKit] built {#made} {kind} wall(s), {parts} parts`)
end

return WallKit
