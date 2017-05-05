
local function new_list()
    local head
    local tail
    local count = 0

    local list = {}

    function list.pop()
        if count > 0 then
            local value = head.value
            head = head.next
            count = count - 1
            if count == 0 then
                tail = nil
            end
            return value
        end
    end

    function list.push(value)
        local t = {value=value}
        if tail then
            tail.next = t
        end
        tail = t
        count = count + 1
        if not head then
            head = t
        end
        return count
    end

    function list.free(num)
        local l = {}
        if num > count then
            num = count
        end
        for i = 1, num do
            l[i] = list.pop()
        end
        return l
    end

    function list.count()
        return count
    end

    return list
end

return new_list
