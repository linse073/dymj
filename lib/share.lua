local skynet = require "skynet"
local sharedata = require "sharedata"
local sprotoloader = require "sprotoloader"
local crit_zone = require "crit_zone"
local random = require "random"

local share = {}

skynet.init(function()
    -- share with all agent
    share.textdata = sharedata.query("textdata")

    share.base = sharedata.query("base")
    share.error_code = sharedata.query("error_code")
    share.error_string = sharedata.query("error_string")

    share.msg = sharedata.query("msg")
    share.name_msg = sharedata.query("name_msg")

    share.invalid_mj_card = sharedata.query("invalid_mj_card")

    -- share in current agent
    share.sproto = sprotoloader.load(1)
    share.cz = crit_zone() -- avoid dead lock, there is only one crit_zone in a agent
    share.rand = random()
end)

return share
