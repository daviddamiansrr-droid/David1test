--!strict
-- Purely cosmetic: nearby slimes do a quick squish-pop when they land.
-- Uses Model:ScaleTo locally (server never sees it). Capped per frame.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RANGE = 70
local MAX_PER_FRAME = 4

local SlimeJuice = {}
local lastVy: { [Model]: number } = {}
local busy: { [Model]: boolean } = {}

local function squish(model: Model)
	busy[model] = true
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			conn:Disconnect()
			busy[model] = nil
			return
		end
		local a = (os.clock() - t0) / 0.22
		if a >= 1 then
			pcall(model.ScaleTo, model, 1)
			conn:Disconnect()
			busy[model] = nil
			return
		end
		-- overshoot then settle
		local s = 1 + math.sin(a * math.pi) * 0.14 * (1 - a)
		pcall(model.ScaleTo, model, s)
	end)
end

function SlimeJuice.init()
	local folder = Workspace:WaitForChild("Slimes")
	folder.ChildRemoved:Connect(function(m)
		lastVy[m :: Model] = nil
		busy[m :: Model] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local camPos = cam.CFrame.Position
		local fired = 0
		for _, m in folder:GetChildren() do
			local model = m :: Model
			local root = model.PrimaryPart
			if not root then
				continue
			end
			if (root.Position - camPos).Magnitude > RANGE then
				lastVy[model] = nil
				continue
			end
			local vy = root.AssemblyLinearVelocity.Y
			local prev = lastVy[model]
			lastVy[model] = vy
			if prev and prev < -10 and vy > -2 and not busy[model] and fired < MAX_PER_FRAME then
				fired += 1
				squish(model)
			end
		end
	end)
end

return SlimeJuice
