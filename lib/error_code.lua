
local pairs = pairs

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
    },
}

local code = {}
local code_string = {}

for k, v in pairs(type_code) do
    local i = k
    for k1, v1 in pairs(v) do
        i = i + 1
        code[k1] = i
        code_string[i] = v1
    end
end

return {code=code, code_string=code_string}
