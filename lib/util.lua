local crypt = require "skynet.crypt"
local skynet = require "skynet"

local pairs = pairs
local ipairs = ipairs
local type = type
local print = print
local tonumber = tonumber
local string = string
local table = table
local tostring = tostring
local b64decode = crypt.base64decode
local b64encode = crypt.base64encode
local hmac_hash = crypt.hmac_hash
local traceback = debug.traceback
local os = os
local date = os.date
local time = os.time
local setmetatable = setmetatable

local util = {}

-- base function
function util.merge(t1, t2)
    for k, v in ipairs(t2) do
        t1[#t1 + 1] = v
    end
end

function util.merge_table(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
end

function util.clone(t)
    local nt = {}
    for k, v in pairs(t) do
        nt[k] = v
    end
    return nt
end

function util.empty(t)
    return next(t) == nil
end

function util.reverse(t)
    local l = #t
    for i = 1, l//2 do
        local j = l - i + 1
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function util.gen_key(serverid, key)
    return string.format("%d@%s", serverid, key)
end

function util.gen_account(logintype, serverid, key)
    return string.format("%d@%d@%s", logintype, serverid, key)
end

local to_string
local function table_to_string(t)
    local ks = {}
    for k, _ in pairs(t) do
        ks[#ks + 1] = k
    end
    table.sort(ks)
    local text = ""
    for _, v in ipairs(ks) do
        text = text .. to_string(t[v])
    end
    return text
end

to_string = function(v)
    local vt = type(v)
    if vt == "string" then
        return v
    elseif vt == "number" or vt == "boolean" then
        return tostring(v)
    elseif vt == "table" then
        return table_to_string(v)
    end
end

function util.check_sign(t, secret)
    local sign = t.sign
    t.sign = nil
    return sign == util.sign(t, secret)
end

function util.sign(t, secret)
    return b64encode(hmac_hash(secret, to_string(t)))
end

function util.update_user()
    return {
        user = {},
    }
end

function util.ltrim(input)
    return string.gsub(input, "^[ \t\n\r]+", "")
end

function util.rtrim(input)
    return string.gsub(input, "[ \t\n\r]+$", "")
end

function util.trim(input)
    input = string.gsub(input, "^[ \t\n\r]+", "")
    return string.gsub(input, "[ \t\n\r]+$", "")
end

function util.split(input, delimiter)
    input = tostring(input)
    delimiter = tostring(delimiter)
    if (delimiter == '') then return false end
    local pos, arr = 0, {}
    -- for each divider found
    for st, sp in function() return string.find(input, delimiter, pos, true) end do
        table.insert(arr, string.sub(input, pos, st - 1))
        pos = sp + 1
    end
    table.insert(arr, string.sub(input, pos))
    return arr
end

function util.dump(value, desciption, nesting)
    if type(nesting) ~= "number" then nesting = 3 end

    local lookupTable = {}
    local result = {}

    local function _v(v)
        if type(v) == "string" then
            v = "\"" .. v .. "\""
        end
        return tostring(v)
    end

    local tb = util.split(traceback("", 2), "\n")
    skynet.error("dump from: " .. util.trim(tb[3]))

    local function _dump(value, desciption, indent, nest, keylen)
        desciption = desciption or "<var>"
        spc = ""
        if type(keylen) == "number" then
            spc = string.rep(" ", keylen - string.len(_v(desciption)))
        end
        if type(value) ~= "table" then
            result[#result + 1] = string.format("%s%s%s = %s", indent, _v(desciption), spc, _v(value))
        elseif lookupTable[value] then
            result[#result + 1] = string.format("%s%s%s = *REF*", indent, desciption, spc)
        else
            lookupTable[value] = true
            if nest > nesting then
                result[#result + 1] = string.format("%s%s = *MAX NESTING*", indent, desciption)
            else
                result[#result + 1] = string.format("%s%s = {", indent, _v(desciption))
                local indent2 = indent.."    "
                local keys = {}
                local keylen = 0
                local values = {}
                for k, v in pairs(value) do
                    keys[#keys + 1] = k
                    local vk = _v(k)
                    local vkl = string.len(vk)
                    if vkl > keylen then keylen = vkl end
                    values[k] = v
                end
                table.sort(keys, function(a, b)
                    if type(a) == "number" and type(b) == "number" then
                        return a < b
                    else
                        return tostring(a) < tostring(b)
                    end
                end)
                for i, k in ipairs(keys) do
                    _dump(values[k], k, indent2, nest + 1, keylen)
                end
                result[#result + 1] = string.format("%s}", indent)
            end
        end
    end
    _dump(value, desciption, "- ", 1)

    for i, line in ipairs(result) do
        skynet.error(line)
    end
end

function util.day_time(t)
    local st = date("*t", t)
    if st.hour >= 4 then
        st.day = st.day + 1
    end
    st.hour = 4
    st.min = 0
    st.sec = 0
    return time(st)
end

function util.week_time(t)
    local st = date("*t", t)
    if st.hour >= 4 then
        return (st.wday + 5) % 7 + 1
    else
        return (st.wday + 4) % 7 + 1
    end
end

function util.parse_time(t)
    local year, month, day, hour, min, sec = string.match(t, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    local st = {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    }
    return time(st)
end

function util.cmd_wrap(cmd, wrap)
    setmetatable(cmd, {
        __index = function(self, key)
            local v = wrap[key]
            if v then
                local f = function(...)
                    return v(wrap, ...)
                end
                cmd[key] = f
                return f
            end
        end,
    })
end

local timer_protocol = {
	routine = "call_routine",
	second_routine = "call_second_routine",
	day_routine = "call_day_routine",
	once_routine = "call_once_routine",
}
function util.timer_wrap(cmd)
    local timer = require "timer"
    setmetatable(cmd, {
        __index = function(self, key)
            local v = timer_protocol[key]
            if v then
                local f = function(...)
					return timer[v](...)
                end
                cmd[key] = f
                return f
            end
        end,
    })
end

function util.shuffle(card, rand)
    local len = #card
    for i = 1, len-1 do
        local r = rand.randi(i, len)
        card[i], card[r] = card[r], card[i]
    end
end

local function encode_char(char)
    return "%" .. string.format("%02X", string.byte(char))
end
function util.url_encode(input)
    -- convert line endings
    input = string.gsub(tostring(input), "\n", "\r\n")
    -- escape all characters but alphanumeric, '.' and '-'
    input = string.gsub(input, "([^%w%.%- ])", encode_char)
    -- convert spaces to "+" symbols
    return string.gsub(input, " ", "+")
end

local function decode_char(h)
    return string.char(tonumber(h, 16))
end
function util.url_decode(input)
    input = string.gsub(input, "+", " ")
    input = string.gsub(input, "%%(%x%x)", decode_char)
    return string.gsub(input, "\r\n", "\n")
end

function util.url_query(q)
    local t = {}
    for k, v in pairs(q) do
        t[#t+1] = string.format("%s=%s", util.url_encode(k), util.url_encode(v))
    end
    return table.concat(t, "&")
end

function util.mongo_find(db, func, ...)
    local key = skynet.call(db, "lua", "find", ...)
    local r = skynet.call(db, "lua", "get_next", key)
    while r do
        func(r)
        r = skynet.call(db, "lua", "get_next", key)
    end
end

return util
