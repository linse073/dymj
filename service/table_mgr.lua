local skynet = require "skynet"
local list = require "tool.list"
local random = require "random"

local assert = assert
local pcall = pcall
local string = string
local ipairs = ipairs
local math = math
local floor = math.floor

local rand
local table_list = {}
local number_list = {}
local free_list = list()

local function new_number()
    local number = rand.randi(200000, 999999)
    if number_list[number] then
        repeat
            number = number - 1
            if not number_list[number] then
                return number
            end
        until number < 200000
        repeat
            number = number + 1
            if not number_list[number] then
                return number
            end
        until number > 999999
    else
        return number
    end
    assert(false, "Table full")
end

local function new_table(count)
    local t = {}
    for i = 1, count do
        local number = new_number()
        number_list[number] = true
        t[i] = {
            agent = skynet.newservice("chess_table", number),
            number = number,
            use = false,
        }
    end
    for k, v in ipairs(t) do
        table_list[v.agent] = v
        number_list[v.number] = v
        free_list.push(v)
    end
end

local function del_table(count)
    local t = free_list.free(count)
    for k, v in ipairs(t) do
        -- NOTICE: logout may call skynet.exit, so you should use pcall.
        pcall(skynet.call, v, "lua", "exit")
    end
end

local CMD = {}

function CMD.new()
    local len = free_list.count()
    local info
    if len > 0 then
        info = free_list.pop()
        assert(not info.use, "Free table has use flag.")
        info.use = true
        if len <= 50 then
            skynet.fork(new_table, 50)
        end
    else
        local number = new_number()
        number_list[number] = true
        local agent = skynet.newservice("chess_table", number)
        info = {
            agent = agent,
            number = number,
            use = true,
        }
        table_list[agent] = info
        number_list[number] = info
    end
    return info.agent
end

function CMD.free(agent)
    local info = assert(table_list[agent], string.format("No table service %d.", agent))
    if info.use then
        info.use = false
        local len = free_list.push(info)
        if len >= 150 then
            skynet.fork(del_table, 50)
        end
    end
end

function CMD.get(number)
    local info = number_list[number]
    if info and info.use then
        return info.agent
    end
end

function CMD.open()
    rand = random()
    rand.init(floor(skynet.time()))
    new_table(100)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        skynet.retpack(f(...))
	end)
end)
