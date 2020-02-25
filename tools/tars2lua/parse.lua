local lex = require "lex"

function new_VarType(t)
    local o = {
		Type = t,            -- basic type
		Unsigned = false,    -- whether unsigned
		TypeSt = "",         -- custom type name, such as an enumerated struct,at this time Type=tkName
		CType = nil,         -- make sure which type of custom type is,tkEnum, tkStruct
		TypeK = nil,         -- vector's member variable,the key of map
		TypeV = nil          -- the value of map
	}
	return o
end

-- StructMember member struct.
function new_StructMember()
    local o = {
		Tag = 0, --    int32
		Require = false, -- bool
		Type = nil, -- VarType
		Key  = "",   --string -- after the uppercase converted key
		KeyStr = "", -- string -- original key
		Default = "", -- string
		DefType = ""
	}
	return o
end

-- StructInfo record struct information.
function new_StructInfo()
    local o = {
		TName        = "",
		Mb           = {}, -- members
		DependModule = {}
	}
	return o
end

-- ArgInfo record argument information.
function  new_ArgInfo()
    local o = {
	    Name = "", --  string
		IsOut = false, -- bool
		Type = nil, -- *VarType
	}
	return o
end

-- FunInfo record function information.
function new_FunInfo()
    local o = {
		Name = "", --   string -- after the uppercase converted name
		NameStr = "", -- string -- original name
		HasRet = false, --  bool
		RetType = nil, -- *VarType
		Args = {} --   []ArgInfo
	}
	return o
end

-- InterfaceInfo record interface information.
function new_InterfaceInfo()
    local o = {
		TName = "", --       string
		Fun = {}, --         []FunInfo
		DependModule = {} --map[string]bool
	}
	return o
end

-- EnumMember record member information.
function new_EnumMember(k,v)
    local o = {
		Key = k,  -- string
		Value = v -- int32
	}
	return o
end

-- EnumInfo record EnumMember information include name.
function new_EnumInfo()
    local o = {
		TName = "", --string
		Mb = {},--    []EnumMember
	}
	return o
end

--ConstInfo record const information.
function new_ConstInfo()
    local o = {
		Type = nil,-- *VarType
		Key = "",  -- string
		Value = "", -- string
	}
	return o
end

--HashKeyInfo record hashkey information.
function new_HashKeyInfo()
    local o = {
		Name = "", --   string
		Member = {}-- []string
	}
	return o
end

-- Parse record information of parse file.

local M = {}

M.__index = M

function M.new()
    local o = {
		Source = "", -- string
	
		Module = "", --      string
		OriginModule = "", -- string
		Include = {}, --       []string
	
		Struct     = {}, --[]StructInfo
		Interface  = {}, --[]InterfaceInfo
		Enum       = {}, --[]EnumInfo
		Const      = {}, --[]ConstInfo
		HashKey    = {}, --[]HashKeyInfo
	
		-- have parsed include file
		IncParse  = {}, --[]*Parse
	
		lex   = nil, --*LexState
		t     = nil, --*Token
		lastT = nil  --*Token
	}
	return setmetatable(o,M)
end

function M:parseErr(err)
	local line = "0"
	if self.t ~= nil then
		line = tostring(self.t.Line)
	end

	error(self.Source + ": " + line + ". " + err)
end

function M:next()
	self.lastT = self.t
	self.t = self.lex:NextToken()
end

function M:expect(t)
	self:next()
	if self.t.T ~= t then
		self:parseErr("expect " + lex.TokenMap[t])
	end
end

function M:makeUnsigned(utype)
	if utype.Type == "tkTInt" or utype.Type == "tkTShort" or utype.Type == "tkTByte" then
		utype.Unsigned = true
	else
		self:parseErr("type " + lex.TokenMap[utype.Type] + " unsigned decoration is not supported")
	end
end

function M:parseType()
	local vtype = new_VarType(self.t.T)

	if vtype.Type == "tkName" then
		vtype.TypeSt = self.t.S.S
	elseif vtype.Type == "tkTInt" or vtype.Type == "tkTBool" or vtype.Type == "tkTShort" or 
	       vtype.Type == "tkTLong" or vtype.Type == "tkTByte" or vtype.Type == "tkTFloat" or 
		   vtype.Type == "tkTDouble" or vtype.Type == "tkTString" then
		-- no nothing
	elseif vtype.Type == "tkTVector" then
		self:expect("tkShl")
		self:next()
		vtype.TypeK = self:parseType()
		self:expect("tkShr")
	elseif vtype.Type == "tkTMap" then
		self:expect("tkShl")
		self:next()
		vtype.TypeK = self:parseType()
		self:expect("tkComma")
		self:next()
		vtype.TypeV = self:parseType()
		self:expect("tkShr")
	elseif vtype.Type == "tkUnsigned" then
		self:next()
		local utype = self:parseType()
		self:makeUnsigned(utype)
		return utype
	else
		self:parseErr("expert type")
	end
	return vtype
end

function M:parseEnum()
	local enum = new_EnumInfo()
	self:expect("tkName")
	enum.TName = self.t.S.S
	for _, v in ipairs(self.Enum) do
		if v.TName == enum.TName then
			self:parseErr(enum.TName + " Redefine.")
		end
	end
	self:expect("tkBracel")

	local it = 0
	while(true) do
		self:next()
		if self.t.T == "tkBracer" then
			return
		elseif self.t.T == "tkName" then
			local k = self.t.S.S
			self:next()
			if self.t.T == "tkComma" then
				local m = new_EnumMember(k, it)
				table.insert(enum.Mb, m)
				it = it + 1
			elseif self.t.T == "tkBracer" then
				local m = new_EnumMember(k, it)
				table.insert(enum.Mb, m)
				return
			elseif self.t.T == "tkEq" then
				self:expect("tkInteger")
				it = tonumber(self.t.S.I)
				local m = new_EnumMember(k, it)
				table.insert(enum.Mb, m)
				it = it + 1
				self:next()
				if self.t.T == "tkBracer" then
					return
				elseif self.t.T == "tkComma" then
				else
					self:parseErr("expect , or }")
				end
			end
		end
	end
	self:expect("tkSemi")
	table.insert(self.Enum, enum)
end

function M:parseStructMemberDefault(m)
	m.DefType = self.t.T
	if self.t.T == "tkInteger" then
		if not isNumberType(m.Type.Type) and m.Type.Type ~= "tkName" then
			-- enum auto defined type ,default value is number.
			self:parseErr("type does not accept number")
		end
		m.Default = self.t.S.S
	elseif self.t.T == "tkFloat" then
		if not isNumberType(m.Type.Type) then
			self:parseErr("type does not accept number")
		end
		m.Default = self.t.S.S
	elseif self.t.T == "tkString" then
		if isNumberType(m.Type.Type) then
			self:parseErr("type does not accept string")
		end
		m.Default = "\"" + p.t.S.S + "\""
	elseif self.t.T == "tkTrue" then
		if m.Type.Type ~= tkTBool then
			self:parseErr("default value format error")
		end
		m.Default = "true"
	elseif self.t.T == "tkFalse" then
		if m.Type.Type ~= "tkTBool" then
			self:parseErr("default value format error")
		end
		m.Default = "false"
	elseif self.t.T == "tkName" then
		m.Default = self.t.S.S
	else
		self:parseErr("default value format error")
	end
end

function M:parseStructMember()
	-- tag or end
	self:next()
	if self.t.T == "tkBracer" then
		return nil
	end
	if self.t.T ~= "tkInteger" then
		self:parseErr("expect tags.")
	end
	local m = new_StructMember()
	m.Tag = tonumber(self.t.S.I)

	-- require or optional
	self:next()
	if self.t.T == "tkRequire" then
		m.Require = true
	elseif self.t.T == "tkOptional" then
		m.Require = false
	else
		self:parseErr("expect require or optional")
	end

	-- type
	self:next()
	if not isType(self.t.T) and self.t.T ~= "tkName" and self.t.T ~= "tkUnsigned" then
		self:parseErr("expect type")
	else
		m.Type = self:parseType()
	end

	-- key
	self:expect("tkName")
	m.Key = self.t.S.S

	self:next()
	if self.t.T == "tkSemi" then
		return m
	end
	if self.t.T ~= "tkEq" then
		self:parseErr("expect ; or =")
	end
	if self.t.T == "tkTMap" or self.t.T == "tkTVector" or self.t.T == "tkName" then
		self:parseErr("map, vector, custom type cannot set default value")
	end

	-- default
	self:next()
	self:parseStructMemberDefault(m)
	self:expect("tkSemi")

	return m
end

function M:checkTag(st)
	local set = {}
	for _, v in ipairs(st.Mb) do
		if set[v.Tag] then
			self:parseErr("tag = " + strconv.Itoa(int(v.Tag)) + ". have duplicates")
		end
		set[v.Tag] = true
	end
end

function M:sortTag(st)
	table.sort(st.Mb)
end

function M:parseStruct()
	local st = new_StructInfo()
	self:expect("tkName")
	st.TName = self.t.S.S
	for _, v in ipairs(self.Struct) do
		if v.TName == st.TName then
			self:parseErr(st.TName + " Redefine.")
		end
	end
	self:expect("tkBracel")

	while(true) do
		local m = self:parseStructMember()
		if m == nil then
			break
		end
		table.insert(st.Mb, m)
	end
	self:expect("tkSemi") --semicolon at the end of the struct.

	self:checkTag(st)
	self:sortTag(st)

	table.insert(self.Struct, st)
end

function M:parseInterfaceFun()
	local fun = new_FunInfo()
	self:next()
	if self.t.T == "tkBracer" then
		return nil
	end
	if self.t.T == "tkVoid" then
		fun.HasRet = false
	elseif not isType(self.t.T) and self.t.T ~= "tkName" and self.t.T ~= "tkUnsigned" then
		self:parseErr("expect type")
	else
		fun.HasRet = true
		fun.RetType = self:parseType()
	end
	self:expect("tkName")
	fun.Name = self.t.S.S
	self:expect("tkPtl")

	self:next()
	if self.t.T == "tkShr" then
		return fun
	end

	-- No parameter function, exit directly.
	if self.t.T == "tkPtr" then
		self:expect("tkSemi")
		return fun
	end

	while(true) do
		local arg = new_ArgInfo()
		if self.t.T == "tkOut" then
			arg.IsOut = true
			self:next()
		else
			arg.IsOut = false
		end

		arg.Type = self:parseType()
		self:next()
		if self.t.T == tkName then
			arg.Name = self.t.S.S
			self:next()
		end

		table.insert(fun.Args, arg)

		if self.t.T == "tkComma" then
			self:next()
		elseif self.t.T == "tkPtr" then
			self:expect("tkSemi")
			break
		else
			self:parseErr("expect , or )")
		end
	end
	return fun
end

function M:parseInterface()
	local itf = new_InterfaceInfo()
	self:expect("tkName")
	itf.TName = self.t.S.S
	for _, v in ipairs(self.Interface) do
		if v.TName == itf.TName then
			self:parseErr(itf.TName + " Redefine.")
		end
	end
	self:expect("tkBracel")

	while(true) do
		local fun = self:parseInterfaceFun()
		if fun == nil then
			break
		end
		table.insert(itf.Fun, fun)
	end
	self:expect("tkSemi") --semicolon at the end of struct.
	self.Interface = append(self.Interface, itf)
end

function M:parseConst()
	local m = new_ConstInfo()

	-- type
	self:next()
	if self.t.T == "tkTVector" or self.t.T == "tkTMap" then
		self:parseErr("const no supports type vector or map.")
	elseif self.t.T == "tkTBool" or self.t.T == "tkTByte" or self.t.T == "tkTShort" or
		self.t.T == "tkTInt" or self.t.T == "tkTLong" or self.t.T == "tkTFloat" or
		self.t.T == "tkTDouble" or self.t.T == "tkTString" or self.t.T == "tkUnsigned" then
		m.Type = self:parseType()
	else
		self:parseErr("expect type.")
	end

	self:expect("tkName")
	m.Key = self.t.S.S

	self:expect("tkEq")

	-- default
	self:next()
	if self.t.T == "tkInteger" or self.t.T =="tkFloat" then
		if not isNumberType(m.Type.Type) then
			self:parseErr("type does not accept number")
		end
		m.Value = self.t.S.S
	elseif self.t.T == "tkString" then
		if isNumberType(m.Type.Type) then
			self:parseErr("type does not accept string")
		end
		m.Value = "\"" + p.t.S.S + "\""
	elseif self.t.T == "tkTrue" then
		if m.Type.Type ~= "tkTBool" then
			self:parseErr("default value format error")
		end
		m.Value = "true"
	elseif self.t.T == "tkFalse" then
		if m.Type.Type ~= "tkTBool" then
			self:parseErr("default value format error")
		end
		m.Value = "false"
	else
		self:parseErr("default value format error")
	end
	self:expect("tkSemi")

	table.append(self.Const, m)
end

function M:parseHashKey()
	local hashKey = new_HashKeyInfo()
	self:expect("tkSquarel")
	self:expect("tkName")
	hashKey.Name = self.t.S.S
	self:expect("tkComma")
	while(true) do
		self:expect("tkName")
		table.insert(hashKey.Member, self.t.S.S)
		self:next()
		local t = self.t
		if t.T == "tkSquarer" then
			self:expect("tkSemi")
			self.HashKey = append(self.HashKey, hashKey)
			return
		elseif t.T == "tkComma" then
		else
			self:parseErr("expect ] or ,")
		end
	end
end

function M:parseModuleSegment()
	self:expect("tkBracel")

	while(true) do
		self:next()
		local t = self.t
		if t.T == "tkBracer" then
			self:expect("tkSemi")
			return
		elseif t.T == "tkConst" then
			self:parseConst()
		elseif t.T == "tkEnum" then
			self:parseEnum()
		elseif t.T == "tkStruct" then
			self:parseStruct()
		elseif t.T == "tkInterface" then
			self:parseInterface()
		elseif t.T == "tkKey" then
			self:parseHashKey()
		else
			self:parseErr("not except " + lex.TokenMap[t.T])
		end
	end
end

function M:parseModule()
	self:expect("tkName")

	if self.Module ~= "" then
		self:parseErr("do not repeat define module")
	end
	self.Module = self.t.S.S

	self:parseModuleSegment()
end

function M:parseInclude()
	self:expect("tkString")
	table.insert(self.Include, self.t.S.S)
end

-- Looking for the true type of user-defined identifier
function M:findTNameType(tname)
	for _, v in ipairs(self.Struct) do
		if self.Module+"::"+v.TName == tname then
			return "tkStruct", self.Module
		end
	end

	for _, v in ipairs(self.Enum) do
		if self.Module+"::"+v.TName == tname then
			return "tkEnum", self.Module
		end
	end

	for _, pInc in ipairs(self.IncParse) do
		local ret, mod = pInc.findTNameType(tname)
		if ret ~= "tkName" then
			return ret, mod
		end
	end
	-- not find
	return "tkName", self.Module
end

function M:findEnumName(ename)
	if strings.Contains(ename, "::") then
		ename = strings.Split(ename, "::")[1]
	end
	local cmb -- *EnumMember
	local cenum -- *EnumInfo
	for ek, enum in ipairs(self.Enum) do
		for mk, mb in ipairs(enum.Mb) do
			if mb.Key == ename then
				if cmb == nil then
					cmb = enum.Mb[mk]
					cenum = self.Enum[ek]
				else
					self.parseErr(ename + " name conflict [" + cenum.TName + "::" + cmb.Key + " or " + enum.TName + "::" + mb.Key)
					return nil, nil
				end
			end
		end
	end
	for _, pInc in ipairs(self.IncParse) do
		if cmb == nil then
			cmb, cenum = pInc:findEnumName(ename)
		else
			break
		end
	end
	return cmb, cenum
end

local function addToSet(m, module_name)
	if m == nil then
		m = {}
	end
	m[module_name] = true
	return m
end

function M:checkDepTName(ty, dm)
	if ty.Type == "tkName" then
		local name = ty.TypeSt
		if strings.Count(name, "::") == 0 then
			name = self.Module + "::" + name
		end

		local mod = ""
		ty.CType, mod = self:findTNameType(name)
		if ty.CType == "tkName" then
			self:parseErr(ty.TypeSt + " not find define")
		end
		if mod ~= self.Module then
			addToSet(dm, mod)
		else
			-- the same Module ,do not add self.
			ty.TypeSt = strings.Replace(ty.TypeSt, mod+"::", "", 1)
		end
	elseif ty.Type == "tkTVector" then
		self:checkDepTName(ty.TypeK, dm)
	elseif ty.Type == "tkTMap" then
		self:checkDepTName(ty.TypeK, dm)
		self:checkDepTName(ty.TypeV, dm)
	end
end

-- analysis custom type，whether have definition
function M:analyzeTName()
	for i, v in ipairs(self.Struct) do
		for _, v in ipairs(v.Mb) do
			local ty = v.Type
			self:checkDepTName(ty, self.Struct[i].DependModule)
		end
	end

	for i, v in ipairs(self.Interface) do
		for _, v in ipairs(v.Fun) do
			for _, v in ipairs(v.Args) do
				local ty = v.Type
				self:checkDepTName(ty, self.Interface[i].DependModule)
			end
			if v.RetType ~= nil then
				self:checkDepTName(v.RetType, self.Interface[i].DependModule)
			end
		end
	end
end

function M:analyzeDefault()
	for _, v in ipairs(self.Struct) do
		for i, r in ipairs(v.Mb) do
			if r.Default ~= "" and r.DefType == tkName then
				local mb, enum = self:findEnumName(r.Default)
				if mb == nil then
					self:parseErr("can not find default value" + r.Default)
				end
				v.Mb[i].Default = enum.TName + "_" + mb.Key
			end
		end
	end
end

-- TODO analysis key[]，have quoted the correct struct and member name.
function M:analyzeHashKey()
end

function M:analyzeDepend()
	for _, v in ipairs(self.Include) do
		local pInc = lex.ParseFile(v)
		table.insert(self.IncParse, pInc)
		print("parse include: ", v)
	end

	self:analyzeDefault()
	self:analyzeTName()
	self:analyzeHashKey()
end

function M:parse()
	while(true) do
		self:next()
		local t = self.t
		if t.T == tkEos then
			break
		elseif t.T == tkInclude then
			self:parseInclude()
		elseif t.T == tkModule then
			self:parseModule()
		else
			self:parseErr("Expect include or module.")
		end
	end
	self:analyzeDepend()
end

function M.newParse(path, buff)
	local p = M.new()
	
	p.Source = path
	p.lex = lex.NewLexState(path, buff)

	return p
end

-- ParseFile parse a file,return grammar tree.
function M.ParseFile(path)
	local f = io.open(path)
	if f == nil then
		self:parseErr("file read error: " + path)
	end

    local buff = f:read()
	f:close()

	local p = M.newParse(path, buff)
	p:parse()

	return p
end

--Initial capitalization
function upperFirstLatter(s)
	if #s == 0 then
		return ""
	end
	if #s == 1 then
		return strings.ToUpper(string(s[0]))
	end
	return strings.ToUpper(string(s[0])) + s[1:]
end

-- === rename area ===
-- 0. rename module
function M:rename()
	self.OriginModule = self.Module
	self.Module = upperFirstLatter(self.Module)
end

return M