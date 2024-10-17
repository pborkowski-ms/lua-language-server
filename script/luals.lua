Class   = require 'class'.declare
New     = require 'class'.new
Delete  = require 'class'.delete
Type    = require 'class'.type
IsValid = require 'class'.isValid

---@class LuaLS
ls = {}

ls.util    = require 'utility'
ls.fsu     = require 'tools.fs-utility'
ls.inspect = require 'tools.inspect'
ls.encoder = require 'tools.encoder'
ls.gc      = require 'tools.gc'
ls.json    = require 'tools.json'
package.loaded['json'] = ls.json
package.loaded['json-beautify'] = require 'tools.json-beautify'
package.loaded['jsonc']         = require 'tools.jsonc'
package.loaded['json-edit']     = require 'tools.json-edit'
ls.linkedTable = require 'tools.linked-table'
ls.pathTable   = require 'tools.path-table'
ls.uri         = require 'tools.uri'
ls.task        = require 'tools.task'
ls.timer       = require 'tools.timer'

require 'tools.log'

ls.config  = require 'config'

require 'file'
ls.files   = New 'FileManager' ()

require 'node'
require 'vm'

return ls
