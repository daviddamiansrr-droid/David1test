--!strict
-- Item ids are plain strings so they serialise straight into DataStores:
--   "slime:Bubble"        normal slime
--   "slime:Bubble+Fizz"   largo (types sorted so A+B == B+A)
--   "food:Berry"
--   "gem:Fizz"

local Config = require(script.Parent.Config)

local ItemIds = {}

export type Parsed = {
	Kind: string, -- "slime" | "food" | "gem"
	A: string, -- slime type / food name / gem type
	B: string?, -- largo second type
}

local orderIndex: { [string]: number } = {}
for i, name in Config.SlimeOrder do
	orderIndex[name] = i
end

function ItemIds.slime(a: string, b: string?): string
	if b and b ~= a then
		if orderIndex[b] < orderIndex[a] then
			a, b = b, a
		end
		return `slime:{a}+{b :: string}`
	end
	return `slime:{a}`
end

function ItemIds.food(name: string): string
	return `food:{name}`
end

function ItemIds.gem(t: string): string
	return `gem:{t}`
end

-- Returns nil for anything malformed or referencing unknown types.
-- Used to sanitise DataStore contents and remote input.
function ItemIds.parse(id: any): Parsed?
	if typeof(id) ~= "string" or #id > 40 then
		return nil
	end
	local kind, rest = string.match(id, "^(%a+):([%a%+]+)$")
	if not kind or not rest then
		return nil
	end
	if kind == "slime" then
		local a, b = string.match(rest, "^(%a+)%+(%a+)$")
		if a and b then
			if not Config.Slimes[a] or not Config.Slimes[b] or a == b then
				return nil
			end
			return { Kind = "slime", A = a, B = b }
		end
		if Config.Slimes[rest] then
			return { Kind = "slime", A = rest }
		end
	elseif kind == "food" then
		if Config.Foods[rest] then
			return { Kind = "food", A = rest }
		end
	elseif kind == "gem" then
		if Config.Slimes[rest] then
			return { Kind = "gem", A = rest }
		end
	end
	return nil
end

function ItemIds.colors(id: string): (Color3, Color3?)
	local p = ItemIds.parse(id)
	if not p then
		return Color3.new(1, 1, 1), nil
	end
	if p.Kind == "food" then
		return Config.Foods[p.A].Color, nil
	end
	local a = Config.Slimes[p.A].Color
	local b = if p.B then Config.Slimes[p.B].Color else nil
	return a, b
end

function ItemIds.display(id: string): string
	local p = ItemIds.parse(id)
	if not p then
		return "?"
	end
	if p.Kind == "food" then
		return Config.Foods[p.A].Display
	elseif p.Kind == "gem" then
		return `{Config.Slimes[p.A].Display} Gem`
	elseif p.B then
		return `{Config.Slimes[p.A].Display}-{Config.Slimes[p.B].Display} Largo`
	end
	return `{Config.Slimes[p.A].Display} Slime`
end

-- Union of diets for a (possibly largo) slime.
function ItemIds.eats(a: string, b: string?, food: string): boolean
	if Config.Slimes[a].Diet[food] then
		return true
	end
	return b ~= nil and Config.Slimes[b].Diet[food] == true
end

return ItemIds
