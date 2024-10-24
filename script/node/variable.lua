---@class Node.Variable: Class.Base, Node.CacheModule
local M = Class 'Node.Variable'

Extends('Node.Variable', 'Node.CacheModule')

M.kind = 'variable'

---@alias Node.Key string | number | boolean | Node

---@param scope Scope
---@param name Node.Key
---@param parent? Node.Variable
function M:__init(scope, name, parent)
    if type(name) == 'table' then
        ---@cast name Node
        self.key = name
    else
        ---@cast name -Node
        self.key = scope.node.value(name)
    end
    self.scope = scope
    self.parent = parent
end

---@type LinkedTable
M.nodes = nil

---@param node Node.Type
---@return Node.Variable
function M:addType(node)
    if not self.nodes then
        self.nodes = ls.linkedTable.create()
    end
    self.nodes:pushTail(node)
    self:flushCache()

    return self
end

---@param node Node.Type
---@return Node.Variable
function M:removeType(node)
    if not self.nodes then
        return self
    end
    self.nodes:pop(node)
    self:flushCache()

    return self
end

---@type LinkedTable
M.assigns = nil

---@param node Node
---@return Node.Variable
function M:addAssign(node)
    if not self.assigns then
        self.assigns = ls.linkedTable.create()
    end
    self.assigns:pushTail(node)
    self:flushCache()

    return self
end

---@param node Node
---@return Node.Variable
function M:removeAssign(node)
    if not self.assigns then
        return self
    end
    self.assigns:pop(node)
    self:flushCache()

    return self
end

---@type LinkedTable
M.classes = nil

---@param node Node.Type
---@return Node.Variable
function M:addClass(node)
    if not self.classes then
        self.classes = ls.linkedTable.create()
    end
    self.classes:pushTail(node)
    self:flushCache()

    return self
end

---@param node Node.Type
---@return Node.Variable
function M:removeClass(node)
    if not self.classes then
        return self
    end
    self.classes:pop(node)
    self:flushCache()

    return self
end

---@type Node.Table?
M.fields = nil

---@param self Node.Variable
---@return Node.Table?
---@return boolean
M.__getter.fields = function (self)
    if not self.childs then
        return nil, false
    end
    local t = self.scope.node.table()
    for k, v in pairs(self.childs) do
        if type(k) ~= 'table' then
            ---@cast k -Node
            k = self.scope.node.value(k)
        end
        t:addField {
            key = k,
            value = v.value,
        }
    end
    return t, true
end

---@type table<Node, Node.Variable>?
M.childs = nil

---@param key Node.Key
---@param path? Node.Key[]
---@return Node.Variable
function M:getField(key, path)
    local node = self.scope.node
    local current = self
    if path then
        for _, k in ipairs(path) do
            if type(k) ~= 'table' then
                ---@cast k -Node
                k = node.value(k)
            end
            current = current.childs and current.childs[k]
                    or node.variable(k, current)
        end
    end
    if type(key) ~= 'table' then
        ---@cast key -Node
        key = node.value(key)
    end
    local child = current.childs and current.childs[key]
                or node.variable(key, current)
    return child
end

M.childRefCount = 0

---@param key Node.Key
---@param value Node
---@param path? Node.Key[]
---@return Node.Variable
function M:addField(key, value, path)
    local node = self.scope.node
    local current = self
    current.childRefCount = current.childRefCount + 1
    if not current.childs then
        current.childs = {}
    end

    if path then
        for _, k in ipairs(path) do
            if type(k) ~= 'table' then
                ---@cast k -Node
                k = node.value(k)
            end
            if not current.childs[k] then
                current.childs[k] = node.variable(k, current)
            end
            current = current.childs[k]
            current.childRefCount = current.childRefCount + 1
            if not current.childs then
                current.childs = {}
            end
        end
    end

    if type(key) ~= 'table' then
        ---@cast key -Node
        key = node.value(key)
    end
    if not current.childs[key] then
        current.childs[key] = node.variable(key, current)
    end
    current = current.childs[key]
    current:addAssign(value)
    current.parent:flushCache()

    return self
end

---@param key Node.Key
---@param value Node
---@param path? Node.Key[]
---@return Node.Variable
function M:removeField(key, value, path)
    if not self.childs then
        return self
    end
    ---@type Node.Variable
    local current = self
    local currentChilds = current.childs
    if not currentChilds then
        return self
    end
    current.childRefCount = current.childRefCount - 1
    if current.childRefCount == 0 then
        current.childs = nil
    end

    local node = self.scope.node
    if path then
        for _, k in ipairs(path) do
            if type(k) ~= 'table' then
                ---@cast k -Node
                k = node.value(k)
            end
            ---@type Node.Variable
            current = currentChilds[k]
            if not current then
                return self
            end
            currentChilds = current.childs
            if not currentChilds then
                return self
            end
            current.childRefCount = current.childRefCount - 1
            if current.childRefCount == 0 then
                current.childs = nil
                if current.parent then
                    current.parent.childs[k] = nil
                end
            end
        end
    end

    if type(key) ~= 'table' then
        ---@cast key -Node
        key = node.value(key)
    end
    current = currentChilds[key]
    if not current then
        return self
    end
    current:removeAssign(value)
    current.parent:flushCache()

    return self
end

---@type Node
M.value = nil

---@param self Node.Variable
---@return Node
---@return true
M.__getter.value = function (self)
    local node = self.scope.node
    if self.classes then
        local union = node.union(self.classes:toArray())
        return union.value, true
    end
    if self.nodes then
        local union = node.union(self.nodes:toArray())
        return union.value, true
    end
    if self.assigns then
        local union = node.union(self.assigns:toArray())
        return union.value, true
    end
    return self.scope.node.UNKNOWN, true
end

M.hideInView = false

---@param skipLevel? integer
---@return string
function M:view(skipLevel)
    ---@type Node.Variable[]
    local path = {}
    local current = self
    local tooLong
    while current do
        path[#path+1] = current
        current = current.parent
        if #path >= 8 then
            tooLong = true
            break
        end
    end
    if not tooLong then
        for i = #path, 2, -1 do
            local var = path[i]
            if var.hideInView then
                path[i] = nil
            else
                break
            end
        end
    end

    local views = {}
    if tooLong then
        views[#views+1] = '...'
    end
    views[#views+1] = path[#path].key:viewAsKey(skipLevel)
    for i = #path - 1, 1, -1 do
        local var = path[i]
        local view = var.key:viewAsKey(skipLevel)
        if view:sub(1, 1) ~= '[' then
            view = '.' .. view
        end
        views[#views+1] = view
    end

    return table.concat(views)
end
