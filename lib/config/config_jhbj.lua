
local config = {}

config.server = {
    {
        serverid = 1,
        servername = "server01",
    },
}

config.gate = {
    ip = "jhserver.dyzx7.cn",
    port = 10888,
    maxclient = 65535,
    servername = "gate01",
}

config.redis = {
    host = "127.0.0.1",
    port = 6379,
    base = 0,
    name = {
    },
}

config.mongo = {
    host = "127.0.0.1",
    name = {
	    "account",
        "user",
        "info",
        "offline",
        "status",
        "register",
        "user_record",
        "record_info",
        "record_detail",
        "iap_log",
        "charge_log",
    },
    index = {
        {"account", {"key", unique=true}},
        {"user", {"id", unique=true}},
        {"info", {"id", unique=true}},
        {"offline", {"id", unique=true}},
        {"status", {"key", unique=true}},
        {"user_record", {"id", unique=true}},
        {"record_info", {"id", unique=true}},
        {"record_info", {"expire", expireAfterSeconds=7*24*60*60}},
        {"record_detail", {"id", unique=true}},
        {"record_detail", {"expire", expireAfterSeconds=8*24*60*60}},
        {"iap_log", {"transaction_id", unique=true}},
        {"charge_log", {"id", unique=true}},
    },
}

return config
