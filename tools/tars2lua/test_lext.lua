local lex = require "lex"

local source = "../../proto/test.tars"
local f = io.open(source)
local str = f:read("*a")
f:close()

local lx = lex.NewLexState(source,str)

repeat
    local item = lx:NextToken()
    if not item then
        break
    end
    print("========item==========")
    print("type: " .. (item.t or "nil"))
    if item.s then
        if item.s.s then
            print("string: " .. item.s.s)
        end
        if item.s.f then
            print("float: " .. item.s.f)
        end
        if item.s.i then
            print("integer: " .. item.s.i)
        end
    end
until false

