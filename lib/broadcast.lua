local skynet = require "skynet"
local sharedata = require "sharedata"
local sprotoloader = require "sprotoloader"

local assert = assert
local string = string
local pairs = pairs

local sproto
local name_msg

skynet.init(function()
    sproto = sprotoloader.load(1)
    name_msg = sharedata.query("name_msg")
end)

local function pack_msg(msg, info)
    if sproto:exist_type(msg) then
        info = sproto:pencode(msg, info)
    end
    local id = assert(name_msg[msg], string.format("No protocol %s.", msg))
    return string.pack(">s2", string.pack(">I2", id) .. info)
end

local function broadcast(msg, info, range, exclude)
    local c = pack_msg(msg, info)
    for k, v in pairs(range) do
        if v.id ~= exclude and v.agent then
            -- TODO: offline
            skynet.send(v.agent, "lua", "notify", c)
        end
    end
end

return broadcast
