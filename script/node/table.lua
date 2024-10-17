---@class Node.Table: Node
---@operator bor(Node?): Node
---@operator band(Node?): Node
---@operator shr(Node): boolean
---@overload fun(fields?: table): Node.Table
local M = ls.node.register 'Node.Table'

M.kind = 'table'

---@class Node.Field
---@field key Node
---@field value Node

---@param fields? table
function M:__init(fields)
    self.fields = ls.linkedTable.create()
    if fields then
        for k, v in pairs(fields) do
            if type(k) ~= 'table' then
                k = ls.node.value(k)
            end
            if type(v) ~= 'table' then
                v = ls.node.value(v)
            end
            self.fields:pushTail { key = k, value = v }
        end
    end
end

---@param field Node.Field
---@return Node.Table
function M:addField(field)
    self:flushCache()
    self.fields:pushTail(field)
    return self
end

---@param field Node.Field
---@return Node.Table
function M:removeField(field)
    self:flushCache()
    self.fields:pop(field)
    return self
end

function M:flushCache()
    self.sortedFields = nil
    self.literals = nil
    self.types = nil
    self.others = nil
    self.hasGeneric = nil
end

function M:isEmpty()
    return self.fields:getSize() == 0
end

---@type table<string|number|boolean, Node>
M.literals = nil
---@type table<string, Node>
M.types = nil
---@type Node.Field[]
M.others = nil

---@package
function M:classifyFields()
    local literals = {}
    local types = {}
    local others = {}
    self.literal = literals
    self.types = types
    self.others = others

    ---@param field Node.Field
    for field in self.fields:pairsFast() do
        local key = field.key
        if key.kind == 'value' then
            ---@cast key Node.Value
            local k = key.literal
            literals[k] = literals[k] | field.value
        elseif key.typeName then
            types[key.typeName] = types[key.typeName] | field.value
        else
            others[#others+1] = field
        end
        if key.kind == 'union' then
            ---@cast key Node.Union
            for _, v in ipairs(key.values) do
                if v.kind == 'value' then
                    ---@cast v Node.Value
                    local k = v.literal
                    literals[k] = literals[k] | field.value
                elseif v.typeName then
                    types[v.typeName] = types[v.typeName] | field.value
                else
                    others[#others+1] = field
                end
            end
        end
    end
end

---@param self Node.Table
---@return table<string|number|boolean, Node>
M.__getter.literals = function (self)
    self:classifyFields()
    return self.literal
end


---@param self Node.Table
---@return table<string, Node>
M.__getter.types = function (self)
    self:classifyFields()
    return self.types
end


---@param self Node.Table
---@return table<Node, Node>
M.__getter.others = function (self)
    self:classifyFields()
    return self.others
end

---获取所有的键。
---@type Node[]
M.keys = nil

---@param self Node.Table
---@return Node[]
---@return true
M.__getter.keys = function (self)
    local keys = {}

    for _, field in ipairs(self.sortedFields) do
        keys[#keys+1] = field.key
    end

    return keys, true
end

---获取所有的值。按key的顺序排序。
---@type Node[]
M.values = nil

---@param self Node.Table
---@return Node[]
---@return true
M.__getter.values = function (self)
    local values = {}

    for _, field in ipairs(self.sortedFields) do
        values[#values+1] = field.value
    end

    return values, true
end

---@type Node.Field[]
M.sortedFields = nil

---@param self Node.Table
---@return { key: Node, value: Node }[]
---@return true
M.__getter.sortedFields = function (self)
    ---@type { key: Node, value: Node }[]
    local values = {}

    local typeOrder = {
        ['number']  = 1,
        ['string']  = 2,
        ['boolean'] = 3,
    }

    for k, v in ls.util.sortPairs(self.literals, function (a, b)
        local ta = type(a)
        local tb = type(b)
        local sa = typeOrder[ta] or 0
        local sb = typeOrder[tb] or 0
        if sa == sb then
            if ta == 'number' or ta == 'string' then
                return a < b
            else
                return a == true
            end
        else
            return sa < sb
        end
    end) do
        values[#values+1] = { key = ls.node.value(k), value = v }
    end

    for k, v in ls.util.sortPairs(self.types) do
        values[#values+1] = { key = ls.node.type(k), value = v }
    end
    for _, field in ipairs(self.others) do
        values[#values+1] = field
    end

    return values, true
end

---@param key string|number|boolean|Node
---@return Node
function M:get(key)
    if key == ls.node.NEVER then
        return ls.node.NEVER
    end
    if key == ls.node.ANY
    or key == ls.node.UNKNOWN then
        return ls.node.union(self.values):getValue(ls.node.NIL)
    end
    if key == ls.node.NIL then
        return ls.node.NIL
    end
    if type(key) ~= 'table' then
        ---@cast key -Node
        return self.literals[key]
            or self:get(ls.node.value(key).nodeType)
            or ls.node.NIL
    end
    if key.kind == 'value' then
        ---@cast key Node.Value
        return self.literals[key.literal]
            or self:get(key.nodeType)
            or ls.node.NIL
    end
    ---@cast key Node
    if key.typeName then
        if self.types[key.typeName] then
            return self.types[key.typeName]
        end
        ---@param field Node.Field
        for field in self.fields:pairsFast() do
            if field.key.kind == 'type' and key:canCast(field.key) then
                return field.value
            end
        end
        return ls.node.NIL
    end
    if key.kind == 'union' then
        ---@cast key Node.Union
        ---@type Node
        local result
        for _, v in ipairs(key.values) do
            local r = self:get(v)
            result = result | r
        end
        return result
    end
    return ls.node.NIL
end

---@param other Node
---@return boolean
function M:onCanBeCast(other)
    if self == other then
        return true
    end
    for _, field in ipairs(self.sortedFields) do
        local v = other:get(field.key)
        if not v:canCast(field.value) then
            return false
        end
    end
    return true
end

---@param other Node
---@return boolean
function M:onCanCast(other)
    if other.kind == 'array' then
        ---@cast other Node.Array
        local myType = self:get(ls.node.INTEGER)
        if myType:canCast(other.head) then
            return true
        elseif myType ~= ls.node.NIL then
            return false
        end
        for k, v in pairs(self.literals) do
            if  type(k) == 'number'
            and k % 1 == 0
            and k >= 1
            and k <= other.len then
                if not v:canCast(other.head) then
                    return false
                end
            end
        end
        return true
    end
    return false
end

function M:view(skipLevel)
    if #self.sortedFields == 0 then
        return '{}'
    end

    local fields = {}

    local childSkipLevel = skipLevel and skipLevel + 1 or nil
    for _, v in ipairs(self.sortedFields) do
        fields[#fields+1] = string.format('%s: %s'
            , v.key:viewAsKey(childSkipLevel)
            , v.value:view(childSkipLevel)
        )
    end

    return '{ ' .. table.concat(fields, ', ') .. ' }'
end

---@param others Node[]
function M:extends(others)
    local literals = self.literals
    local types = self.types

    for _, other in ipairs(others) do
        local value = other.value
        if value.kind == 'table' then
            ---@cast value Node.Table
            for k, v in pairs(value.literals) do
                if literals[k] == nil then
                    literals[k] = v
                end
            end
            for k, v in pairs(value.types) do
                if types[k] == nil then
                    types[k] = v
                end
            end
        end
    end

    for k, v in pairs(literals) do
        self:addField {
            key   = ls.node.value(k),
            value = v,
        }
    end
    for k, v in pairs(types) do
        self:addField {
            key   = ls.node.type(k),
            value = v,
        }
    end
end

---@param self Node.Table
---@return boolean
---@return true
M.__getter.hasGeneric = function (self)
    for field in self.fields:pairsFast() do
        if field.key.hasGeneric or field.value.hasGeneric then
            return true, true
        end
    end
    return false, true
end

function M:resolveGeneric(pack)
    if not self.hasGeneric then
        return self
    end
    local newTable = ls.node.table()
    ---@param field Node.Field
    for field in self.fields:pairsFast() do
        if field.key.hasGeneric
        or field.value.hasGeneric then
            newTable:addField {
                key   = field.key:resolveGeneric(pack),
                value = field.value:resolveGeneric(pack),
            }
        else
            newTable:addField(field)
        end
    end
    return newTable
end

---@param fields? table
---@return Node.Table
function ls.node.table(fields)
    return New 'Node.Table' (fields)
end