--!strict
-- Collision groups:
--   Players   : every character that doesn't own a plot (NOT "Default": Terrain
--               and the map live in Default, and items must still hit those).
--   Fence_i   : plot i's walls, net and lock barrier. Blocks everyone except Owner_i.
--   Owner_i   : characters of plot i's owner (walk through your own fence).
--   Slimes    : slime colliders.
--   Items     : food + gems. Bounce off fences, ignore players.
--   SlimeField: invisible gate field that only stops slimes.

local PhysicsService = game:GetService("PhysicsService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Collision = {}

local function register(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

function Collision.fence(i: number): string
	return `Fence_{i}`
end

function Collision.owner(i: number): string
	return `Owner_{i}`
end

function Collision.init()
	register("Players")
	register("Slimes")
	register("Items")
	register("SlimeField")
	for i = 1, Config.MaxPlots do
		register(Collision.fence(i))
		register(Collision.owner(i))
	end

	-- Items never block players (but still land on terrain/map in Default)
	PhysicsService:CollisionGroupSetCollidable("Items", "Players", false)
	-- SlimeField only touches slimes
	PhysicsService:CollisionGroupSetCollidable("SlimeField", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("SlimeField", "Items", false)

	for i = 1, Config.MaxPlots do
		local owner = Collision.owner(i)
		PhysicsService:CollisionGroupSetCollidable(owner, "Items", false)
		PhysicsService:CollisionGroupSetCollidable(owner, "SlimeField", false)
		PhysicsService:CollisionGroupSetCollidable(owner, Collision.fence(i), false)
	end
end

Collision.PLAYERS = "Players"

function Collision.setCharacterGroup(character: Model, group: string)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

return Collision
