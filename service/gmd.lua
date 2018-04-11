local skynet = require "skynet"
local util = require "util"

local dump = util.dump
local print = print
local tonumber = tonumber
local select = select
local pcall = pcall
local type = type
local string = string
local table = table
local floor = math.floor

local arg = {...}

local CMD = {}

function CMD.test_broadcast()
    local master = skynet.queryservice("mongo_master")
    local user_db = skynet.call(master, "lua", "get", "user")
    util.mongo_find(user_db, dump, nil, {id=true, _id=false})
end

skynet.start(function()
	local command = arg[1]
	local c = CMD[command]
	local ok, list
	if c then
		ok, list = pcall(c, select(2, table.unpack(arg)))
	else
        print(string.format("Invalid command %s.", command))
	end
	if ok then
		if list then
			if type(list) == "string" then
				print(list)
			else
                dump(list)
			end
		end
        print("OK")
	else
		print("Error:", list)
	end

    skynet.exit()
end)
