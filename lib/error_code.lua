
local pairs = pairs
local ipairs = ipairs
local table = table

local type_code = {
    [0] = {
        OK="成功",
    },

    [1000] = {
        INTERNAL_ERROR="数据错误",
    },

    [1100] = {
        ALREADY_NOTIFY="重复提示",
        ERROR_ARGS="参数错误",
        ERROR_SIGN="签名错误",
    },

    [3000] = {
        NOT_JOIN_CHESS="尚未加入棋局",
        CHESS_ROLE_FULL="棋局人数已满",
        ALREAD_IN_CHESS="已经在棋局中",
        NO_CHESS="棋牌游戏不存在",
        NOT_IN_CHESS="不在棋局中",
        ALREADY_READY="已经准备好了",
        ERROR_CHESS_STATUS="棋局状态错误",
        ERROR_CHESS_NUMBER="棋局编号错误",
        ERROR_CHESS_NAME="游戏不匹配",
    },
}

local code = {}
local code_string = {}

for k, v in pairs(type_code) do
    local t = {}
    for k1, v1 in pairs(v) do
        t[#t+1] = k1
    end
    table.sort(t)
    for k1, v1 in ipairs(t) do
        local i = k + k1
        local s = v[v1]
        code[s] = i
        code_string[i] = s
    end
end

return {code=code, code_string=code_string}
