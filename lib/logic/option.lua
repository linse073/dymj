
local string = string

local function jdmj(rule)
    local r = {pack=rule}
    local p, c = string.unpack("BB", rule)
    r.aa_pay = (p == 1)
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 10, 40, 10
    else
        r.total_count, r.total_card, r.single_card = 20, 80, 20
    end
    return r
end

local function dymj(rule)
    local r = {pack=rule}
    local p, c, i = string.unpack("BBB", rule)
    r.aa_pay = (p ~= 1)
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 8, 4, 1
    else
        r.total_count, r.total_card, r.single_card = 16, 8, 2
    end
    r.ip = (i == 1)
    return r
end

local function test_dymj(rule)
    local r = {pack=rule}
    local p, c, i = string.unpack("BBB", rule)
    r.aa_pay = (p ~= 1)
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 8, 0, 0
    else
        r.total_count, r.total_card, r.single_card = 16, 0, 0
    end
    r.ip = (i == 1)
    return r
end

local function jd13(rule)
    local r = {pack=rule}
    local p, c, n, kt, k = string.unpack("BBBBB", rule)
    r.aa_pay = (p == 1)
    r.user = 5 - n
    assert(r.user>=2 and r.user<=4, string.format("jd13 error user: %d.", r.user))
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
    local p, c, n, kt, k, i = string.unpack("BBBBBB", rule)
    r.aa_pay = (p ~= 1)
    r.user = 5 - n
    assert(r.user>=2 and r.user<=4, string.format("dy13 error user: %d.", r.user))
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 12, r.user, 1
    else
        r.total_count, r.total_card, r.single_card = 24, r.user*2, 2
    end
    r.key_type = kt
    r.key = k
    r.ip = (i == 1)
    return r
end

local function jhbj(rule)
    local r = {pack=rule}
    local p, c, n, e, g, i = string.unpack("BBBBBB", rule)
    r.aa_pay = (p == 1)
    r.user = 6 - n
    assert(r.user>=2 and r.user<=5, string.format("jhbj error user: %d.", r.user))
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 8, r.user, 1
    elseif c == 2 then
        r.total_count, r.total_card, r.single_card = 12, r.user, 1
    else
        r.total_count, r.total_card, r.single_card = 16, r.user, 1
    end
    r.extra = (e == 1)
    r.give_up = (g == 1)
    r.ip = (i == 1)
    return r
end

local function jhbj6(rule)
    local r = {pack=rule}
    local p, c, n, e, g, i = string.unpack("BBBBBB", rule)
    r.aa_pay = (p == 1)
    r.user = 7 - n
    assert(r.user>=2 and r.user<=6, string.format("jhbj6 error user: %d.", r.user))
    if c == 1 then
        r.total_count, r.total_card, r.single_card = 8, r.user, 1
    elseif c == 2 then
        r.total_count, r.total_card, r.single_card = 12, r.user, 1
    else
        r.total_count, r.total_card, r.single_card = 16, r.user, 1
    end
    r.extra = (e == 1)
    r.give_up = (g == 1)
    r.ip = (i == 1)
    return r
end

local function dy4(rule)
    local r = {pack=rule}
    local o1, o2, o3, o4, o5, o6 = string.unpack("BBBBBB", rule)
    r.aa_pay = (o1 ~= 1)
    if o2 == 1 then
        r.total_count, r.total_card, r.single_card = 4, 4, 1
    elseif o2 == 2 then
        r.total_count, r.total_card, r.single_card = 8, 8, 1
    else
        r.total_count, r.total_card, r.single_card = 16, 12, 1
    end
    r.ip = (o3 == 1)
    r.alone_award = (o4 == 1)
    r.split = (o5 == 1)
    r.extra_king = (o6 == 1)
    return r
end

local option = {
    dymj = dymj,
    test_dymj = test_dymj,
    jdmj = jdmj,
    test_jdmj = jdmj,
    jd13 = jd13,
    dy13 = dy13,
    jhbj = jhbj,
    jhbj6 = jhbj6,
    dy4 = dy4,
}

return option
