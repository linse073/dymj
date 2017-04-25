local skynet = require "skynet"
local queue = require "skynet.queue"
local util = require "util"

local loginservice = tonumber(...)

local assert = assert

local gen_key = util.gen_key
local gen_account = util.gen_account
local cs = queue()
local status_db
local account_db
local status_key
local status
local config

local CMD = {}

local function check_account(info)
    local namekey = gen_account(info.loginType, config.serverid, info.uid)
    local account = skynet.call(account_db, "lua", "findOne", {key=namekey})
    if account then
        if info.register then
            return false, nil, "name exist"
        else
            if info.password then
                if info.password == account.password then
                    return false, account
                else
                    return false, nil, "password error"
                end
            else
                return false, account
            end
        end
    else
        local accountid = status.accountid * 10000 + 1000 + config.serverid
        status.accountid = status.accountid + 1
        local account = {
			key = namekey,
			uid = info.uid,
            id = accountid,
            password = info.password,
        }
        skynet.call(account_db, "lua", "safe_insert", account)
        return true, account
    end
end

function CMD.open(conf, gatename)
    config = conf
    local master = skynet.queryservice("mongo_master")
    status_db = skynet.call(master, "lua", "get", "status")
    account_db = skynet.call(master, "lua", "get", "account")
    status_key = gen_key(config.serverid, "status")
    status = skynet.call(status_db, "lua", "findOne", {key=status_key})
    if not status then
        status = {
            accountid = 1,
        }
    end
    local server_mgr = skynet.queryservice("server_mgr")
    skynet.call(server_mgr, "lua", "register", config.serverid, skynet.self())
    skynet.call(loginservice, "lua", "register_server", conf, gatename, skynet.self())
end

function CMD.shutdown()
    skynet.call(loginservice, "lua", "unregister_server", config.servername)
end

function CMD.gen_account(info)
    local new, account, errmsg = cs(check_account, info)
    if new then
		skynet.call(status_db, "lua", "update", {key=status_key}, {["$set"]={accountid=status.accountid}})
    end
    return new, account, errmsg
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, command, ...)
		local f = assert(CMD[command])
        skynet.retpack(f(...))
	end)
end)
