local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local sharedata = require "sharedata"
local proto = require "proto"

local string = string
local pairs = pairs
local ipairs = ipairs
local assert = assert
local tonumber = tonumber

skynet.start(function()
    -- share data
    local textdata = require("data.text")
    local base = require("base")

    sharedata.new("textdata", textdata)

    sharedata.new("base", base)
    local error_code = require("error_code")
    sharedata.new("error_code", error_code.code)
    sharedata.new("error_string", error_code.code_string)

    sharedata.new("msg", proto.msg)
    sharedata.new("name_msg", proto.name_msg)

    local card = {10, 20, 30, 32, 34, 36, 38, 39, 40, 42, 44}
    local invalid_mj_card = {}
    for k, v in ipairs(card) do
        invalid_mj_card[v] = v
    end
    sharedata.new("invalid_mj_card", invalid_mj_card)

    -- protocol
    local file = skynet.getenv("root") .. "proto/proto.sp"
    sprotoloader.register(file, 1)
	-- don't call skynet.exit(), because sproto.core may unload and the global slot become invalid
end)
