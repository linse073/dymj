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
    sharedata.new("error_code", require("error_code"))

    sharedata.new("msg", proto.msg)
    sharedata.new("name_msg", proto.name_msg)

    -- protocol
    local file = skynet.getenv("root") .. "proto/proto.sp"
    sprotoloader.register(file, 1)
	-- don't call skynet.exit(), because sproto.core may unload and the global slot become invalid
end)
