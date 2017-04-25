local skynet = require "skynet"
local util = require "util"

local proc = {}
local game = {proc = proc}

local name = {"role", "gm"}
local module = {}
game.module = module
local revert_module = {}
local name_module = {}
local len = #name
for k, v in ipairs(name) do
	local m = require("game." .. v)
	module[k] = m
	revert_module[len-k+1] = m
	name_module[v] = m
	util.merge_table(proc, m.proc)
end

function game.iter(fname, ...)
	for k, v in ipairs(module) do
		local func = v[fname]
		if func then
			func(...)
		end
	end
end

function game.riter(fname, ...)
	for k, v in ipairs(revert_module) do
		local func = v[fname]
		if func then
			func(...)
		end
	end
end

function game.one(mname, fname, ...)
	local m = assert(name_module[mname], string.format("No module %s.", mname))
	local func = assert(m[fname], string.format("No function %s in %s.", fname, mname))
	return func(...)
end

function game.init(data)
	game.data = data
	game.iter("init")
end

function game.exit()
	game.riter("exit")
	game.data = nil
end

return game