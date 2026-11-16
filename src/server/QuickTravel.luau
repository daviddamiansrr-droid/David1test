--!strict
-- Fast travel so walking home from the far areas isn't a chore.
--
--  * "Home" button (client fires Travel:"home"): teleports you to your ranch.
--    Cooldown per player, and blocked for a while after you steal so it can't
--    be used to escape with stolen slimes.
--  * Travel pads: any part tagged "TravelPad" with a string attribute PadName.
--    Give it a Target attribute naming another pad and stepping on it sends
--    you there (one-way; give both pads a Target for two-way). Use this for the
--    area 3 -> area 4 shortcut, or a pad near every portal back to the ranch row.
--    A pad with Target = "Home" sends you to your own ranch.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlotService = require(script.Parent.PlotService)

local T = Config.Travel
local NotifyRemote = Remotes.event("Notify")

local QuickTravel = {}
local lastHome: { [Player]: number } = {}
local lastPad: { [Player]: number } = {}

local function blockedReason(player: Player): string?
	local stoleAt = player:GetAttribute("StoleAt")
	if typeof(stoleAt) == "number" then
		local left = T.BlockedAfterSteal - (Workspace:GetServerTimeNow() - stoleAt)
		if left > 0 then
			return `You just stole a slime! Run it home ({math.ceil(left)}s)`
		end
	end
	return nil
end

local function teleport(player: Player, cf: CFrame)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 then
		return
	end
	char:PivotTo(cf)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

function QuickTravel.home(player: Player)
	local t = os.clock()
	local remaining = T.HomeCooldown - (t - (lastHome[player] or -math.huge))
	if remaining > 0 then
		NotifyRemote:FireClient(player, `Home is recharging ({math.ceil(remaining)}s)`, "warn")
		return
	end
	local reason = blockedReason(player)
	if reason then
		NotifyRemote:FireClient(player, reason, "error")
		return
	end
	local cf = PlotService.spawnPoint(player)
	if not cf then
		NotifyRemote:FireClient(player, "You don't have a ranch yet", "error")
		return
	end
	lastHome[player] = t
	teleport(player, cf)
	player:SetAttribute("HomeReadyAt", Workspace:GetServerTimeNow() + T.HomeCooldown)
end

local function findPad(name: string): BasePart?
	for _, p in CollectionService:GetTagged("TravelPad") do
		if p:IsA("BasePart") and p:GetAttribute("PadName") == name then
			return p
		end
	end
	return nil
end

local function hookPad(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end
	pad.CanTouch = true
	pad.Touched:Connect(function(hit)
		local char = hit.Parent
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player or hit.Name ~= "HumanoidRootPart" then
			return
		end
		local t = os.clock()
		if t - (lastPad[player] or 0) < T.PadCooldown then
			return
		end
		local target = pad:GetAttribute("Target")
		if typeof(target) ~= "string" then
			return
		end
		lastPad[player] = t
		if target == "Home" then
			QuickTravel.home(player)
			return
		end
		local dest = findPad(target)
		if dest then
			-- land just in front of the destination pad, not on it (no ping-pong)
			local out = dest.CFrame * CFrame.new(0, dest.Size.Y / 2 + 3, -(dest.Size.Z / 2 + 4))
			teleport(player, out)
		end
	end)
end

function QuickTravel.init()
	Remotes.event("Travel").OnServerEvent:Connect(function(player, what)
		if what == "home" then
			QuickTravel.home(player)
		end
	end)
	for _, p in CollectionService:GetTagged("TravelPad") do
		hookPad(p)
	end
	CollectionService:GetInstanceAddedSignal("TravelPad"):Connect(hookPad)
	Players.PlayerRemoving:Connect(function(player)
		lastHome[player] = nil
		lastPad[player] = nil
	end)
end

return QuickTravel
