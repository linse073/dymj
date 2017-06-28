
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

    [1200] = {
        ROLE_ALREADY_ENTER="已经登陆",
    },

    [3000] = {
        NOT_JOIN_CHESS="尚未加入房间",
        CHESS_ROLE_FULL="该房间人数已满",
        ALREAD_IN_CHESS="已经在房间中",
        NO_CHESS="游戏不存在",
        NOT_IN_CHESS="不在房间中",
        ALREADY_READY="已经准备好了",
        ERROR_CHESS_STATUS="房间状态错误",
        ERROR_CHESS_NUMBER="该房间不存在",
        ERROR_CHESS_NAME="游戏不匹配",
        ERROR_DEAL_INDEX="发牌索引不匹配",
        NO_OUT_CARD="出牌不存在",
        INVALID_CARD="非法牌",
        ERROR_OPERATION="操作不合法",
        CHI_COUNT_LIMIT="你已经吃三摊了",
        WAIT_FOR_OTHER="请等待其他牌友",
        ALREADY_PASS="已经过了",
        CONCLUDE_CARD_LIMIT="尚未流局",
        OUT_CARD_LIMIT="出牌限制",
        ALREADY_REPLY="已经回答",
        ERROR_OUT_INDEX="出牌索引不匹配",
        CAN_NOT_HU="只能自摸胡",
        IN_CLOSE_PROCESS="解散过程中",
        NOT_IN_CLOSE="尚未解散房间",
        ROOM_CARD_LIMIT="房卡数量不足，请联系群主购买",
        NO_RECORD="战绩已删除",
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
        code[v1] = i
        code_string[i] = v[v1]
    end
end

return {code=code, code_string=code_string}
