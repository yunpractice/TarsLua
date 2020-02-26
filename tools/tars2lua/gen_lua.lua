local gE = false

local gAddServant = true

local M = {}

M.__index = M

--GenGo record go code information.
function M.new()
    local o = {
		code     = "",   --bytes.Buffer
		vc       = 0,    --int      var count. Used to generate unique variable names
		I        = {},   --[]string imports with path
		path     = "",   --string
		prefix   = "",   --string
		tarsPath = "",   --string
		p        = nil   --*Parse
	}
	setmetatable(o,M)
	return o
end

function M:genErr(err)
	error(err)
end

function M:saveToSourceFile()
	local prefix = self.prefix
	local dir = prefix .. self.p.Module
    os.execute("mkdir " .. dir)
	local f = io.open(dir .. "/" .. self.p.Module .. ".lua","w")
	f:write(self.code)
    f:close()
end

function M:genHead()
	self.code = self.code .. string.format([[==[[
-- Package %s comment
-- This file war generated by tars2lua 0.1 
-- Generated from %s

local M = {}
]]==]],self.p.Module,self.path)
end

function M:genFoot()
    self.code = self.code .. "return M"
end

function M:genImport(mo)
	for _, p in ipairs(self.I) do
		if strings.HasSuffix(p, "/"+mo) then
			self.code = self.code .. "\"" .. p .. "\"\n"
			return
		end
	end
	if gAddServant == true then
		self.code = self.code .. "\"" .. upperFirstLatter(mo) .. "\"\n"
	else
		self.code = self.code .."\"" .. mo .. "\"\n"
	end
end

function M:genStructPackage(st) -- StructInfo

	--"tars/protocol/codec"
	self.code = self.code .."\"" .. self.tarsPath .. "/protocol/codec\"\n"
	for k,_ in pairs(st.DependModule) do
		self.genImport(k)
	end
	self.code = self.code ..")" + "\n"

end

function M:genIFPackage(itf)
	self.code = self.code .. "--package " .. self.p.Module .. "\n\n"
	self.code = self.code .. "\"" .. self.tarsPath .. "/protocol/res/requestf\"\n"
	self.code = self.code .. "m \"" .. self.tarsPath .. "/model\"\n"
	self.code = self.code .. "\"" .. self.tarsPath .. "/protocol/codec\"\n"
	self.code = self.code .. "\"" .. self.tarsPath .. "/util/tools\"\n"
	self.code = self.code .. "\"" .. self.tarsPath .. "/util/current\"\n"

	if gAddServant then
		self.code = self.code .. "\"" .. self.tarsPath .. "\"\n"
	end
	for k,_ in ipairs(itf.DependModule) do
		self:genImport(k)
	end
	self.code = self.code .. ")\n"
end

local default_m = {
    tkTBool = "false",
	tkTInt = "0",
	tkTShort = "0",
	tkTByte = "0",
	tkTLong = "0",
	tkTFloat = "0.0",
	tkTDouble = "0.0",
	tkTString = "",
	tkTVector = "{}",
	tkTMap = "{}"
}

function M:genType(ty) --VarType
	local v = default_m[ty]
	if v then
	    return v
	end
	if ty == tkName:
		--Actrually ret is useless here
		--ret = strings.Replace(ty.TypeSt, "::", ".", -1)
	end
	gen:genErr("Unknow Type " .. lex.TokenMap[ty.Type])
end

function M:genStructDefine(st) -- StructInfo
	self.code = self.code .. "--" .. st.TName .. " strcut implement\n"
	self.code = self.code .. string.format(
[[==[[
-- %s strcut implement
local %s = {}

M.%s = %s

%s.__index = %s

function %s.new()
	local o = {
]]==]],st.TName,st.TName,st.TName,st.TName,st.TName)

	for _, v in ipairs(st.Mb)
		self.code = self.code .. "\t\t" .. v.Key .. " = " .. self:genType(v.Type) .. ",\n"
	end

	self.code = self.code .. string.format([[==[[
	}
	setmetatable(o,%s)
	return o
}
]]==]],st.TName)
end

function M:genFunResetDefault(st) --StructInfo
	self.code = self.code .. "function " .. st.TName .. ":resetDefault()\n"

	for _, v in ipairs(st.Mb) do
		if v.Default ~= "" then
		    self.code = self.code .. "\tself." .. v.Key .. " = " .. v.Default .. "\n"
		end
	end
	self.code = self.code .. "end\n"
end

function errString(hasRet)
	local retStr = (hasRet and "return ret, err") or "return err"
	return "if err then\n\t" .. retStr .. "\nend"
end

function M:genWriteSimpleList(mb,prefix,hasRet) --mb *StructMember, prefix string, hasRet bool) {
	tag = mb.Tag
	local unsign = ""
	if mb.Type.TypeK.Unsigned then
		unsign = "u"
	end
	local errStr = errString(hasRet)
    self.code = self.code .. "_os.WriteHead(codec.SIMPLE_LIST, " .. tag .. ")\n"
    self.code = self.code .. "_os.WriteHead(codec.BYTE, 0)\n"
    self.code = self.code .. "_os.Write_int32(#" .. prefix .. mb.Key .. ",0)\n"
    self.code = self.code .. "_os.Write_slice_" .. unsign + "int8(" .. prefix .. mb.Key .. ")\n"
end

function M:genWriteVector(mb,prefix,hasRet) --mb *StructMember, prefix string, hasRet bool)
	-- SIMPLE_LIST
	if mb.Type.TypeK.Type == "tkTByte" and not mb.Type.TypeK.Unsigned then
		self:genWriteSimpleList(mb, prefix, hasRet)
		return
	end

	-- LIST
	local tag = mb.Tag
	local vname = prefix + mb.Key

	self.code = self.code .. "	_os.WriteHead(codec.LIST, " .. tag ..")\n"
    self.code = self.code .. "	_os.Write_int32(#" .. vname .. ", 0)\n"
	self.code = self.code .. "	for _, v in ipairs(" .. vname .. ") do\n"
	self:genWriteVar(mb.Type.TypeK,"	v", hasRet)

	self.code = self.code .. "	end\n"
end

function M:genWriteStruct(mb,prefix,hasRet) --mb *StructMember, prefix string, hasRet bool)
	local tag = mb.Tag
	self.code = self.code .. prefix .. mb.Key .. ".WriteBlock(_os, " .. tag .. ")"
end

function M:genWriteMap(mb,prefix,hasRet) --mb *StructMember, prefix string, hasRet bool)
	local tag = mb.Tag
	local vc = tostring(self.vc)
	local vname = prefix + mb.Key
	self.vc++
	self.code = self.code .. "_os.WriteHead(codec.MAP, " .. tag .. ")"
    self.code = self.code .. "_os.Write_int32(map_len(" .. vname .. "), 0)\n"
    self.code = self.code .. string.format("for k%s, v%s in pairs(%s) do\n",self.vc,self.vc,vname)
    self:genWriteVar(mb.Type.TypeK,"k" .. self.vc, hasRet)
	self:genWriteVar(mb.Type.TypeV,"v" .. self.vc, hasRet)

	self.code = self.code .. "end\n"
end

function M:genWriteVar(v,prefix,hasRet) -- v *StructMember, prefix string, hasRet bool
    local tag = v.Tag
	if v.Type.Type == "tkTVector" then
		self:genWriteVector(v, prefix, hasRet)
	elseif v.Type.Type == "tkTMap" then
		self:genWriteMap(v, prefix, hasRet)
	elseif v.Type.Type == "tkName" then
		if v.Type.CType == "tkEnum" then
			-- tkEnum enumeration processing
			self.code = self.code .. "	_os.Write_int32("prefix .. v.Key .."," .. tag .. ")\n"
		else
			self:genWriteStruct(v, prefix, hasRet)
		end
		self.code = self.code .. "	_os.Write_" .. self:genType(v.Type) .. "(" .. prefix .. v.Key + ", " .. tag ..")\n"
	end
end

function M:genFunWriteBlock(st) -- *StructInfo
	-- WriteBlock function head
	self.code = self.code .. string.format([[==[[--WriteBlock encode struct
function %s:WriteBlock(_os, tag)
	var err error
	_os.WriteHead(codec.STRUCT_BEGIN, tag)
    self:WriteTo(_os)
	_os.WriteHead(codec.STRUCT_END, 0)
end
]]==]],st.TName)
end

function M:genFunWriteTo(st) -- *StructInfo
	self.code = self.code .. string.format([[==[[
-- WriteTo encode struct to buffer
function %s:WriteTo(_os)
	local err
]]==]],st.TName)
	for _, v in ipairs(st.Mb) then
		self:genWriteVar(v, "self.", false)
	end
    self.code = self.code .. "end\n"
end

function M:genReadSimpleList(mb,prefix,hasRet) --mb *StructMember, prefix string, hasRet bool) {
	local unsign = ""
	if mb.Type.TypeK.Unsigned then
		unsign = "u"
	end
	self.code = self.code .. string.format([[==[[
	_is.SkipTo(codec.BYTE, 0, true)
    length = _is.Read_int32(0, true)
    %s = _is.Read_slice_" .. unsign .. "int8(length, true)
]]==]],prefix .. mb.Key)
end

function genForHead(vc)
	local i = "i" .. vc
	local e = "e" .. vc
	return "\tfor " .. i .. "," .. e .. "= 1,length do"
end

function M:genReadVector(mb,prefix,hasRet) --mb *StructMember, prefix string, hasRet bool)
	-- LIST
	local tag = mb.Tag
	local vc = tostring(self.vc)
	self.vc = self.vc + 1
	local r = (mb.Require and "false") or "true"

	if r == "false" then
		self.code = self.code .. "\thave, ty = _is.SkipToNoCheck(" .. tag .. "," .. r .. ")\n"
		self.code = self.code .. "\tif have then"
	else
		self.code = self.code .. "\t_, ty = _is.SkipToNoCheck(" .. tag .. "," .. r .. ")\n"
	end

	self.code = self.code .. [[==[[
	if ty == codec.LIST then
		length,err = _is.Read_int32(0, true)
		%s = {}
]]==]]
    self.code = self.code .. genForHead(self.vc)

	self:genReadVar(mb.Type.TypeK, mb.Key .. "[i" .. vc .. "]", prefix, hasRet)

	self.code = self.code .. "\tend\n"
    self.code = self.code .. "\telseif ty == codec.SIMPLE_LIST then\n"
	if mb.Type.TypeK.Type == "tkTByte" then
		self:genReadSimpleList(mb, prefix, hasRet)
    end
	if r == "false" then
		self.code = self.code .. "\tend\n"
	end
end

function M:genReadStruct(mb,prefix,hasRet) --mb *StructMember, prefix string, hasRet bool
	local tag = mb.Tag
	local r = (mb.Require and "false") or "true"
	self.code = self.code .. prefix .. mb.Key .. ".ReadBlock(_is, " .. tag .. ", " .. r .. ")"
end

function M:genReadMap(mb,prefix,hasRet) -- mb *StructMember, prefix string, hasRet bool
	local tag = mb.Tag
	local vc = tostring(self.vc)
	self.vc = self.vc + 1
	local r = (mb.Require and "false") or "true"
	self.code = self.code .. "	have = _is.SkipTo(codec.MAP, " .. tag .. ", " .. r ..")\n"
	if r == "false" then
		self.code = self.code .. "	if have then\n"
	end
	self.code = self.code .. "	length = _is.Read_int32(0, true)\n"
    self.code = self.code .. "	" .. prefix .. mb.Key .. " = {}\n"
    self.code = self.code .. genForHead(vc)
	self.code = self.code .. "		local k"..vc.. " = " .. self.genType(mb.Type.TypeK) .. "\n"
	self.code = self.code .. "		local v"..vc.. " = " .. self.genType(mb.Type.TypeV) .. "\n"
	self:genReadVar(mb.Type.TypeK, "	k" .. vc, hasRet)
	self.genReadVar(mb.Type.TypeV, "	v" .. vc, hasRet, 1)

	self.code = self.code .. "	" .. prefix .. mb.Key .. "[k" .. vc .. "] = v" .. vc .. "\n"
	if r == "false" then
		self.code = self.code .. "	end\n"
	then
end

function M:genReadVar(v,prefix,hasRet) --v *StructMember, prefix string, hasRet bool
	local r = (v.Require and "false") or "true"

	if v.Type.Type == "tkTVector" then
		self:genReadVector(v, prefix, hasRet)
	elseif v.Type.Type == "tkTMap" then
		self.genReadMap(v, prefix, hasRet)
	elseif v.Type.Type == "tkName" then
		if v.Type.CType == "tkEnum" then
			self.code = self.code .. "\t" .. prefix .. v.Key .. ",err = _is.Read_int32(".. v.Tag .. ", " .. r..")\n"
		else
			self:genReadStruct(v, prefix, hasRet)
		end
	else
		self.code = self.code .. "\t" .. prefix .. v.Key ..",err = _is.Read_" .. self.genType(v.Type) .. "(" .. v.Tag .. ", " .. r..")\n"
    end
end

function M:genFunReadFrom(st) -- *StructInfo
	self.code = self.code .. string.format([[==[[
--ReadFrom reads  from _is and put into struct.
function %s:ReadFrom(_is)
	local err
	local length
	local have
	local ty
	self:resetDefault()

]]==]],st.TName)

	for _, v in ipairs(self.Mb)
		self:genReadVar(v, "self.", false)
	end
	self.code = self.code .. "end\n"
end

function M:genFunReadBlock(st) -- *StructInfo
	self.code = self.code .. [[==[[
-- ReadBlock reads struct from the given tag , require or optional.
function %s:ReadBlock(_is, tag, r)
	local err
	local have
	self:resetDefault()

	have = _is.SkipTo(codec.STRUCT_BEGIN, tag, r)
    if not have then
        if r then
            return fmt.Errorf("require " + st.TName + ", but not exist. tag %d", tag)    
        end
         return nil
    end

    self:ReadFrom(_is)

	err = _is.SkipToStructEnd()
	if err then
		return err
	end
	return nil
end
]]==]],st.TName)
end


function M:genStruct(st) -- *StructInfo
	self.vc = 0
	self:genStructPackage(st)
	self:genStructDefine(st)
	self:genFunResetDefault(st)
	self:genFunReadFrom(st)
	self:genFunReadBlock(st)
	self:genFunWriteTo(st)
	self:genFunWriteBlock(st)
end

function M:makeEnumName(en,mb) --en *EnumInfo, mb *EnumMember
	return upperFirstLatter(en.TName) + "_" + upperFirstLatter(mb.Key)
end

function M:genEnum(en)
	if #en.Mb == 0 then
		return
	end

	self.code = self.code .. "-- enum " .. en.TName .. "\n"
	for _, v in ipairs(en.Mb) do
		self.code = self.code .. "M." .. en.TName .. " = " .. v.Value .. "\n"
	end
	self.code = self.code .. "\n"

	for _, v in ipairs(en.Mb) do
		self.code = self.code .. "local " .. en.TName .. " = " .. v.Value .. "\n"
	end

	self.code = self.code .. "\n\n"
end

function M:genConst(cst)
	if #cst == 0 then
		return
	end

	c:WriteString("\n--const as define in tars file\n")
	for _, v in ipairs(self.p.Const) then
		self.code = self.code .. "M." .. v.Key .. " = " .. v.Value .. "\n"
	end
	self.code = self.code .. "\n"
	
	for _, v in ipairs(self.p.Const) then
		self.code = self.code .. "M." .. v.Key .. " = " .. v.Value .. "\n"
		self.code = self.code .. "local " .. v.Key .. " = " .. v.Value .. "\n"
	end

	self.code = self.code .. "\n\n"
end

function M:genInclude()
	for _, v in ipairs(self.p.IncParse) then
		local gen2 = M.NewGenGo(v.Source,self.prefix,gTarsPath)
		gen2.p = v
		gen2:genAll()
	end
	
	for _, v in ipairs(self.p.Include) then
		self.code = self.code .. "local " .. v .. " = require \"" .. v .. "\"\n" 
	end
	
	self.code = self.code .. "\n"		
end

function M:genAll()
	self:genInclude()

    self:genHead()

	for _, v in ipairs(self.p.Enum) then
		self:genEnum(v)
	end

	self:genConst(self.p.Const)

	for _, v in ipairs(self.p.Struct) then
		self:genStruct(v)
	end

	for _, v in ipairs(self.p.Interface) then
		self:genInterface(v)
	end
	
	self:genFoot()
	self:saveToSourceFile()
end

function M:genInterface(itf) -- *InterfaceInfo)
	self.code = ""
	itf:rename()

	self:genIFPackage(itf)

	self:genIFProxy(itf)
	self:genIFServer(itf)
	self:genIFServerWithContext(itf)
	self:genIFDispatch(itf)
end

function M:genIFProxy(itf) -- *InterfaceInfo
	self.code = self.code .. "//" + itf.TName + " struct\n")
	self.code = self.code .. "type " + itf.TName + " struct {" + "\n")
	self.code = self.code .. "s m.Servant" + "\n")
	self.code = self.code .. "}" + "\n")

	for _, v in ipairs(itf.Fun) do
		self:genIFProxyFun(itf.TName, v, false)
		self:genIFProxyFun(itf.TName, v, true)
	end

	self.code = self.code .. string.format([[==[[
-- SetServant sets servant for the service.
function %s:SetServant(s) -- m.Servant
	self.s = s
end

-- TarsSetTimeout sets the timeout for the servant which is in ms.
function %s:TarsSetTimeout(t)
	self.s.TarsSetTimeout(t)
end

function %s:setMap() --(l int, res *requestf.ResponsePacket,  ctx map[string]string, sts map[string]string)
		if l == 1{
			for k, _ := range(ctx){
				delete(ctx, k)
			}
			for k, v := range(res.Context){
				ctx[k] = v
			}
		}else if l == 2 {
			for k, _ := range(ctx){
				delete(ctx, k)
			}
			for k, v := range(res.Context){
				ctx[k] = v
			}
			for k, _ := range(sts){
				delete(sts, k)
			}
			for k, v := range(res.Status){
				sts[k] = v
			}
		}
		}
	")
end

]]==]],itf.TName)

	if gAddServant then
		self.code = self.code .. string.format([[==[[
-- AddServant adds servant  for the service
function %s:AddServant() --imp _imp" + itf.TName + ", obj string)
  tars.AddServant(_obj, imp, obj)
end

-- AddServant adds servant  for the service with context
function %s:AddServantWithContext() --imp _imp + itf.TName + "WithContext, obj string)
  tars.AddServantWithContext(_obj, imp, obj)
end

]]==]],itf.TName)

end

function M:genIFProxyFun(interfName, fun, withContext) --interfName string, fun *FunInfo, withContext bool
	if withContext then
		self.code = self.code .. "--" + fun.Name + "WithContext is the proxy function for the method defined in the tars file, with the context\n")
		self.code = self.code .. "function " .. interfName .. ":" .. fun.Name .. "WithContext(ctx context.Context,")
	else
		self.code = self.code .. "--" + fun.Name + " is the proxy function for the method defined in the tars file, with the context\n")
		self.code = self.code .. "function " .. interfName .. ":" .. fun.Name .. "("
	end
	for _, v in ipairs(fun.Args) do
		self:genArgs(v)
	end

	self.code = self.code .. "local _opt = {}\n")
	if fun.HasRet then
		self.code = self.code .. "(ret " + self.genType(fun.RetType) + ", err error){" + "\n")
	else
		self.code = self.code .. "(err error)" + "{" + "\n")
	end

	self.code = self.code .. [[==[[
	local length
	local have
	local ty
    ]]==]]
	self.code = self.code .. "_os = codec.NewBuffer()"
	local isOut
	for k, v in ipairs(fun.Args) do
		if v.IsOut then
			isOut = true
		else
			local dummy = {
			    Type = v.Type,
			    Key = v.Name,
			    Tag = int32(k + 1)
			}
			self.genWriteVar(dummy, "", fun.HasRet)
		end
	end
	-- empty args and below separate
	self.code = self.code .. "\n"

	if withContext == false then
		self.code = self.code .. string.format([[==[[
    local _status = {}
    local _context = {}
    if #_opt == 1 then
	    _context =_opt[0]
    elseif #_opt == 2 then
	    _context = _opt[0]
	    _status = _opt[1]
	end

    _resp = requestf.ResponsePacket.new()
    ctx = context.Background()
    self.s.Tars_invoke(ctx, 0, %s, _os.ToBytes(), _status, _context, _resp)
	]]==]],fun.NameStr)
	else
		self.code = self.code .. string.format([[==[[
	local _status = {}
    local _context = {}
    if #_opt == 1 then
	    _context =_opt[0]
    elseif #_opt == 2 then
	    _context = _opt[0]
	    _status = _opt[1]
    end
    _resp = requestf.ResponsePacket.new()
    self.s:Tars_invoke(ctx, 0, %s, _os.ToBytes(), _status, _context, _resp)
	]]==]],fun.NameStr)
	end

	if isOut or fun.HasRet then
		self.code = self.code .. "_is := codec.NewReader(tools.Int8ToByte(_resp.SBuffer))"
	end
	if fun.HasRet then
		local dummy = {
		    Type = fun.RetType,
		    Key = "ret",
		    Tag = 0,
		    Require = true
		}
		self.genReadVar(dummy, "", fun.HasRet)
	end

	for k, v in ipairs(fun.Args) do
		if v.IsOut then
			local dummy = {
			    Type = v.Type,
			    Key = "(*" + v.Name + ")",
			    Tag = int32(k + 1),
			    Require = true
			}
			self.genReadVar(dummy, "", fun.HasRet)
		end
	end

	self.code = self.code .. "self:setMap(_opt, _resp,_context,_status)"

	if fun.HasRet then
		self.code = self.code .. "return ret, nil\n"
	else
		self.code = self.code .. "return nil\n"
	end

	self.code = self.code .. "}\n"
end

function M:genArgs(arg) -- *ArgInfo
	self.code = self.code .. arg.Name + ","
end

function M:genIFServer(itf) -- *InterfaceInfo
	self.code = self.code .. "local " .. itf.TName .. "={}\n"
	for _, v in ipairs(itf.Fun) then
		self:genIFServerFun(v)
	end
	self.code = self.code .. "}\n"
end

function M:genIFServerWithContext(itf) -- *InterfaceInfo
	self.code = self.code .. "local _imp" .. itf.TName .. "WithContext = {" + "\n")
	for _, v in pairs(itf.Fun) do
		self:genIFServerFunWithContext(v)
	end
	self.code = self.code .. "}\n"
end

function M:genIFServerFun(fun) -- *FunInfo
	self.code = self.code .. fun.Name .. "("
	for _, v in ipairs(fun.Args) then
		self:genArgs(v)
	end
	self.code = self.code .. ")("

	if fun.HasRet then
		self.code = self.code .. "ret " + self.genType(fun.RetType) + ", ")
	end
	self.code = self.code .. "err error)" .. "\n"
end

function M:genIFServerFunWithContext(fun) -- *FunInfo
	self.code = self.code .. fun.Name .. "(ctx, "
	for _, v in ipairs(fun.Args) do
		self:genArgs(v)
	end
	self.code = self.code .. ")("

	if fun.HasRet then
		self.code = self.code .. "ret " + self.genType(fun.RetType) + ", "
	end
	self.code = self.code .. "err error)" .. "\n"
end

function M:genSwitchCaseBody(tname,fun) -- tname string, fun *FunInfo
	self.code = self.code .. "function " .. fun.NameStr .. "(ctx , _val ,_os , _is , withContext)\n"
	self.code = self.code .. [[==[[
	local length
	local have
	local ty
	]]==]]

	for k, v in ipairs(fun.Args) do
		self.code = self.code .. "var " .. v.Name .. " " .. self.genType(v.Type)
		if not v.IsOut then
			local dummy = {
				Type = v.Type,
				Key = v.Name,
				Tag = int32(k + 1),
				Require = true
			}
			self:genReadVar(dummy, "", false)
		else
			self.code = self.code .. "\n")
		end
	end

	if fun.HasRet then
		self.code = self.code .. string.format([[==[[
		if withContext == false then
		    local _imp = _val
		    local ret = _imp.%s()
		]]==]]
		for _, v in ipairs(fun.Args) do
			self.code = self.code .. v.Name .. ","
		end
		self.code = self.code .. ")"

		local dummy = {
		    Type = fun.RetType,
		    Key = "ret",
		    Tag = 0,
		    Require = true
		}
		self.genWriteVar(dummy, "", false)
		self.code = self.code .. "else")
		self.code = self.code .. string.format([[==[[
		_imp = _val
		ret, err = _imp.%s(ctx ,")]]==]],fun.Name)
		for _, v in ipairs(fun.Args) do
			self.code = self.code .. v.Name .. ","
		end
		self.code = self.code .. ")"

		local dummy = {
		    Type = fun.RetType,
		    Key = "ret",
		    Tag = 0,
		    Require = true
		}
		self:genWriteVar(dummy, "", false)
		self.code = self.code .. "end\n"

	else
		self.code = self.code .. string.format[[==[[
		if withContext == false then
		    _imp = _val
		    _imp.%s(]]==]],fun.Name)
		for _, v in ipairs(fun.Args) do
			self.code = self.code .. v.Name .. ","
		end
		self.code = self.code .. ")"
		self.code = self.code .. "else"
		self.code = self.code .. string.format([[==[[
		_imp = _val
		err = _imp.%s(]]==]],fun.Name)
		for _, v in ipairs(fun.Args) do
			self.code = self.code .. v.Name .. ","
		end
		self.code = self.code .. ")"
		self.code = self.code .. "}\n")
	end

	for k, v in ipairs(fun.Args)  do
		if v.IsOut then
			local dummy = {
			    Type = v.Type,
			    Key = v.Name,
			    Tag = int32(k + 1),
			    Require = true
			}
			self:genWriteVar(dummy, "", false)
		end
	end
	self.code = self.code .. "return nil\n"
end

function M:genIFDispatch(itf) -- *InterfaceInfo
	for _, v in ipairs(itf.Fun) do
		self:genSwitchCaseBody(itf.TName, v)
	end
	self.code = self.code .. string.format([[==[[
-- Dispatch is used to call the server side implemnet for the method defined in the tars file. withContext shows using context or not
function %s:Dispatch() --(ctx context.Context, _val interface{}, req *requestf.RequestPacket, resp *requestf.ResponsePacket,withContext bool)
]]==]],itf.TName)

	local param = false
	for _, v in ipairs(itf.Fun) do
    	if #v.Args then
			param = true
			break
		end
	end

	if param then
		self.code = self.code .. "_is := codec.NewReader(tools.Int8ToByte(req.SBuffer))")
	end
	self.code = self.code .. "local _os = codec.NewBuffer()\n"

	for _, v in ipairs(itf.Fun)
		self:genSwitchCase(req.SFuncName, itf.TName, v)
	end

	self.code = self.code .. string.format([[==[[
	error ("function mismatch")

    local _status = {}
    local s, ok = current:GetResponseStatus(ctx)
	if ok  and s then
		_status = s
	end
	local _context
	c, ok = current:GetResponseContext(ctx)
	if ok and c then
		_context = c
	end
	local resp = requestf.ResponsePacket.new()
	resp.IVersion = 1
	resp.CPacketType = 0
	resp.IRequestId  = req.IRequestId
	resp.IMessageType  = 0
	resp.IRet = 0
	resp.SBuffer = tools.ByteToInt8(_os.ToBytes())
	resp.Status = _status
	resp.SResultDesc = ""
	resp.Context = _context
    return nil
end
]]==]])
end

function M:genSwitchCase(SFuncName, fun)
	local c = self.code
	self.code = self.code .. string.format([[==[[
	if %s == \"%s\" then
        %s(ctx, _val, _os, _is, withContext)
	end]]==]],SFuncName, fun.NameStr, fun.NameStr)
end

function M:Gen()
	self.p = ParseFile(self.path)
	self:genAll()
end

function M.NewGenGo(path, outdir)
	local o = M.new()
	o.path = path
	o.prefix = outdir
	return o
end

return M
