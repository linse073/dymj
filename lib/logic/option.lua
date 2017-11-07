
local string = string

local function jdmj(rule)
    local r = {pack=rule}
    local p, c = string.unpack("BB", rule)
    if p == 1 then
        r.aa_pay = true
    else
        r.aa_pay = false
    end
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 10, 40, 10
    else
        r.total_count, r.total_card, r.single_card = 20, 80, 20
    end
    return r
end

local function dymj(rule)
    local r = {pack=rule}
    local p, c = string.unpack("BB", rule)
    if p == 1 then
        r.aa_pay = true
    else
        r.aa_pay = false
    end
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 6, 24, 6
    else
        r.total_count, r.total_card, r.single_card = 12, 48, 12
    end
    return r
end

local function jd13(rule)
    local r = {pack=rule}
    local p, c, n, kt, k = string.unpack("BBBBB", rule)
    if p == 1 then
        r.aa_pay = true
    else
        r.aa_pay = false
    end
    if n == 1 then
        r.user = 4
    elseif n == 2 then
        r.user = 3
    else
        r.user = 2
    end
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 20, r.user*10, 10
    else
        r.total_count, r.total_card, r.single_card = 40, r.user*20, 20
    end
    r.key_type = kt
    r.key = k
    return r
end

local function dy13(rule)
    local r = {pack=rule}
    local p, c, n, kt, k = string.unpack("BBBBB", rule)
    if p == 1 then
        r.aa_pay = true
    else
        r.aa_pay = false
    end
    if n == 1 then
        r.user = 4
    elseif n == 2 then
        r.user = 3
    else
        r.user = 2
    end
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 12, r.user*6, 6
    else
        r.total_count, r.total_card, r.single_card = 24, r.user*12, 12
    end
    r.key_type = kt
    r.key = k
    return r
end

local option = {
    dymj = dymj,
    test_dymj = dymj,
    jdmj = jdmj,
    test_jdmj = jdmj,
    jd13 = jd13,
    dy13 = dy13,
}

return option
