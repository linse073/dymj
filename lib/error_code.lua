
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
        IAP_FAIL="苹果内支付失败",
        ALREADY_SHARE="已经分享",
        HAS_INVITE_CODE="已经绑定邀请码",
        INVITE_CODE_ERROR="邀请码错误",
        NO_SHOP_ITEM="商品不存在",
    },

    [3000] = {
        NOT_JOIN_CHESS="尚未加入房间",
        CHESS_ROLE_FULL="对不起，房间人数已满",
        ALREAD_IN_CHESS="已经在房间中",
        NO_CHESS="游戏不存在",
        NOT_IN_CHESS="不在房间中",
        ALREADY_READY="已经准备好了",
        ERROR_CHESS_NUMBER="房间不存在",
        ERROR_CHESS_NAME="游戏不匹配",
        NO_OUT_CARD="不存在这张牌",
        INVALID_CARD="错误牌",
        ERROR_OPERATION="操作失败",
        CHI_COUNT_LIMIT="你已经吃三摊了",
        WAIT_FOR_OTHER="请等待其他牌友",
        ALREADY_PASS="已经过了",
        CONCLUDE_CARD_LIMIT="尚未流局",
        OUT_CARD_LIMIT="出牌限制",
        ALREADY_REPLY="已经回答",
        IN_CLOSE_PROCESS="解散过程中",
        NOT_IN_CLOSE="尚未解散房间",
        ROOM_CARD_LIMIT="钻石数量不足",
        NO_RECORD="战绩已删除",
        ALREADY_DEAL_END="已经发完牌",
        ROOM_CLOSE="房间已解散",
        IP_LIMIT="IP限定，无法加入",
    },

    [4000] = {
        ALREADY_OUT="已经摆牌",
        ALREADY_GIVE_UP="已经弃牌",
    },

    [5000] = {
        NO_CLUB="亲友圈不存在",
        CLUB_FOUND_LIMIT="创建亲友圈已达上限",
        CLUB_LIMIT="亲友圈已达上限",
        CLUB_NAME_EXIST="亲友圈名字已存在",
        ALREADY_IN_CLUB="已经在这个亲友圈",
        ALREADY_APPLY_CLUB="已经申请这个亲友圈",
        NOT_APPLY_CLUB="没有申请这个亲友圈",
        CLUB_PERMIT_LIMIT="亲友圈权限不够",
        NOT_IN_CLUB="不是这个亲友圈成员",
        TARGET_NOT_IN_CLUB="对方不是这个亲友圈成员",
        ALREADY_CLUB_ADMIN="已经是亲友圈管理员",
        NOT_CLUB_ADMIN="不是亲友圈管理员",
        CLUB_ROOM_CARD_LIMIT="亲友圈房卡不足",
        CLUB_ADMIN_LIMIT="亲友圈管理员已达上限",
        CLUB_DAY_CARD_LIMIT="亲友圈每日每人消耗房卡已达上限",
    },

    [6000] = {
        SMALL_POKER="牌太小",
        CAN_NOT_SPLIT_POKER="没有拆牌规则",
        SPLIT_POKER_LIMIT="还有炸弹，不能拆牌",
        ILLEGAL_POKER="出牌错误",
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
