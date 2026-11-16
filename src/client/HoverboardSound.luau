--!strict
-- Hoverboard audio: a smooth looping hum whose pitch and volume follow speed,
-- plus a whoosh when the board starts and stops.
--
-- Two ways to hook it up:
--   1. Tag the board's main part "Hoverboard" with CollectionService.
--      Every client handles every board automatically (riders hear their own,
--      others hear it in 3D).
--   2. Call HoverboardSound.attach(part) yourself; it returns a cleanup function.
-- Speed is read from the part's velocity, so it works with any movement code.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Sounds = require(script.Parent.Sounds)

local TAG = "Hoverboard"
local IDLE_PITCH, MAX_PITCH = 0.85, 1.35
local MAX_SPEED = 60 -- studs/s that maps to max pitch
local MOVING = 2 -- speed above this counts as "riding"

local HoverboardSound = {}

function HoverboardSound.attach(part: BasePart): () -> ()
	local loop = Sounds.loop("HoverLoop", part, 0)
	local baseVolume = Sounds.volumeOf("HoverLoop")
	local moving = false
	local smoothed = 0
	if loop then
		loop.PlaybackSpeed = IDLE_PITCH
		loop:Play()
		TweenService:Create(loop, TweenInfo.new(0.4), { Volume = baseVolume * 0.6 }):Play()
	end
	Sounds.at("HoverStart", part.Position, 1, 1, 80)

	local conn = RunService.Heartbeat:Connect(function(dt)
		if not part.Parent or not loop then
			return
		end
		local v = part.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		-- ease toward the target so pitch glides instead of jittering
		smoothed += (speed - smoothed) * math.min(1, dt * 4)
		local a = math.clamp(smoothed / MAX_SPEED, 0, 1)
		loop.PlaybackSpeed = IDLE_PITCH + (MAX_PITCH - IDLE_PITCH) * a
		loop.Volume = baseVolume * (0.6 + 0.4 * a)

		local nowMoving = speed > MOVING
		if nowMoving ~= moving then
			moving = nowMoving
			if not moving and smoothed > 15 then
				Sounds.at("HoverStop", part.Position, 0.8, 1, 80) -- braking whoosh
			end
		end
	end)

	return function()
		conn:Disconnect()
		if loop then
			Sounds.at("HoverStop", part.Position, 1, 1, 80)
			local tw = TweenService:Create(loop, TweenInfo.new(0.25), { Volume = 0, PlaybackSpeed = 0.6 })
			tw:Play()
			tw.Completed:Connect(function()
				loop:Destroy()
			end)
		end
	end
end

function HoverboardSound.init()
	local active: { [Instance]: () -> () } = {}
	local function add(inst: Instance)
		if inst:IsA("BasePart") and not active[inst] then
			active[inst] = HoverboardSound.attach(inst)
		end
	end
	local function remove(inst: Instance)
		local stop = active[inst]
		if stop then
			active[inst] = nil
			stop()
		end
	end
	for _, inst in CollectionService:GetTagged(TAG) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
end

return HoverboardSound
