---@class Node.Value: Node
---@operator bor(Node?): Node
---@operator shr(Node): boolean
---@overload fun(v: string | number | boolean, quo?: '"' | "'" | '[['): Node.Value
local M = ls.node.register 'Node.Value'

M.kind = 'value'

---@param v string | number | boolean
---@param quo? '"' | "'" | '[['
function M:__init(v, quo)
    local tp = type(v)
    if tp ~= 'string' and tp ~= 'number' and tp ~= 'boolean' then
        error('Invalid value type: ' .. tp)
    end
    ---@cast tp 'string' | 'number' | 'boolean'
    self.literal = v
    ---@type 'string' | 'number' | 'integer' | 'boolean'
    self.typeName = tp
    if tp == 'number' and math.type(v) == 'integer' then
        self.typeName = 'integer'
    end
    self.quo = quo
end

function M:view(skipLevel)
    if self.typeName == 'string' then
        return ls.util.viewString(self.literal, self.quo)
    else
        return ls.util.viewLiteral(self.literal)
    end
end

function M:viewAsKey(skipLevel)
    if self.typeName == 'string' then
        return self.literal
    else
        return '[' .. self:view(skipLevel) .. ']'
    end
end

function M:onCanCast(other)
    if other.kind == 'value' then
        ---@cast other Node.Value
        return self.literal == other.literal
    end
    if other.kind == 'type' then
        ---@cast other Node.Type
        return self.nodeType:canCast(other)
    end
    return false
end

---@type Node.Type
M.nodeType = nil
M.__getter.nodeType = function (self)
    return ls.node.type(self.typeName), true
end

---@type { [string | number | boolean]: Node.Value }
ls.node.VALUE_POOL = setmetatable({}, {
    __mode = 'v',
    __index = function (t, k)
        local v = New 'Node.Value' (k)
        t[k] = v
        return v
    end,
})

---@type { string: Node.Value }
ls.node.VALUE_POOL_STR2 = setmetatable({}, {
    __mode = 'v',
    __index = function (t, k)
        local v = New 'Node.Value' (k, "'")
        t[k] = v
        return v
    end,
})

---@type { string: Node.Value }
ls.node.VALUE_POOL_STR3 = setmetatable({}, {
    __mode = 'v',
    __index = function (t, k)
        local v = New 'Node.Value' (k, '[[')
        t[k] = v
        return v
    end,
})

---@overload fun(v: number): Node.Value
---@overload fun(v: boolean): Node.Value
---@overload fun(v: string, quo?: '"' | "'" | '[['): Node.Value
function ls.node.value(v, quo)
    if quo == "'" then
        return ls.node.VALUE_POOL_STR2[v]
    end
    if quo == '[[' then
        return ls.node.VALUE_POOL_STR3[v]
    end
    return ls.node.VALUE_POOL[v]
end