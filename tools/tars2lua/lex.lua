local EOS = 0

local tkEos = 0
local tkBracel  = 1  -- {
local tkBracer  = 2  -- }
local tkSemi    = 3  -- ;
local tkEq      = 4  -- =
local tkShl     = 5  -- <
local tkShr     = 6  -- >
local tkComma   = 7  -- ,
local tkPtl     = 8  -- (
local tkPtr     = 9  -- )
local tkSquarel = 10 -- [
local tkSquarer = 11 -- ]
local tkInclude = 12 -- #include
 
local tkDummyKeywordBegin = 13
-- keyword
local tkModule = 14
local tkEnum = 15
local tkStruct = 16
local tkInterface = 17
local tkRequire = 18
local tkOptional = 19
local tkConst = 20
local tkUnsigned = 21
local tkVoid = 22
local tkOut = 23
local tkKey = 24
local tkTrue = 25
local tkFalse = 26
local tkDummyKeywordEnd = 27
 
local tkDummyTypeBegin = 28
-- type
local tkTInt = 29
local tkTBool = 30
local tkTShort = 31
local tkTByte = 32
local tkTLong = 33
local tkTFloat = 34
local tkTDouble = 35
local tkTString = 36
local tkTVector = 37
local tkTMap = 38
local tkDummyTypeEnd = 39
 
local tkName  = 40-- variable name
-- value
local tkString = 41
local tkInteger = 42
local tkFloat = 43

-- TokenMap record token  value.
local TokenMap = {
	[tkEos] = "<eos>",

	[tkBracel] =  "{",
	[tkBracer] =  "}",
	[tkSemi] =    ";",
	[tkEq] =      "=",
	[tkShl] =     "<",
	[tkShr] =     ">",
	[tkComma] =   ",",
	[tkPtl] =     "(",
	[tkPtr] =     ")",
	[tkSquarel] = "[",
	[tkSquarer] = "]",
	[tkInclude] = "#include",

	-- keyword
	[tkModule] =    "module",
	[tkEnum] =      "enum",
	[tkStruct] =    "struct",
	[tkInterface] = "interface",
	[tkRequire] =   "require",
	[tkOptional] =  "optional",
	[tkConst] =     "const",
	[tkUnsigned] =  "unsigned",
	[tkVoid] =      "void",
	[tkOut] =       "out",
	[tkKey] =       "key",
	[tkTrue] =      "true",
	[tkFalse] =     "false",

	-- type
	[tkTInt] =    "int",
	[tkTBool] =   "bool",
	[tkTShort] =  "short",
	[tkTByte] =   "byte",
	[tkTLong] =   "long",
	[tkTFloat] =  "float",
	[tkTDouble] = "double",
	[tkTString] = "string",
	[tkTVector] = "vector",
	[tkTMap] =    "map",

	[tkName] = "<name>",
	-- value
	[tkString] =  "<string>",
	[tkInteger] = "<INTEGER>",
	[tkFloat] =   "<FLOAT>"
}

--[[
//SemInfo is struct.
type SemInfo struct {
	I int64
	F float64
	S string
}

//Token record token information.
type Token struct {
	T    TK
	S    *SemInfo
	Line int
}

//LexState record lexical state.
type LexState struct {
	current    byte
	linenumber int

	//t         Token
	//lookahead Token

	tokenBuff bytes.Buffer
	buff      *bytes.Buffer

	source string
}]]--

function isNewLine(b)
	return b == '\r' or b == '\n'
end

function isNumber(b)
	return (b >= '0' and b <= '9') or b == '-'
end

function isHexNumber(b)
	return (b >= 'a' and b <= 'f') or (b >= 'A' and b <= 'F')
end

function isLetter(b)
	return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '_'
end

function isType(t)
	return t > tkDummyTypeBegin and t < tkDummyTypeEnd
end

function isNumberType(t)
	if t == tkTInt or t == tkTBool or  t == tkTShort or  t == tkTByte or  t == tkTLong or  t == tkTFloat or  t == tkTDouble then
		return true
	end

	return false
end

local LexState = {}

function LexState:lexErr(err)
	local line = tostring(self.linenumber)
	error(self.source + ": " + line + ".    " + err)
end

function LexState:incLine()
	local old = self.current
	self:next() -- skip '\n' or '\r'
	if isNewLine(self.current) and self.current ~= old then
		self:next() -- skip '\n\r' or '\r\n'
	end
	self.linenumber = self.linenumber + 1
end

function LexState:readNumber()
	local hasDot = false
	local isHex = false
	repeat
	    if isNumber(self.current)  or  self.current == '.'  or  self.current == 'x'  or  self.current == 'X'  or  (isHex and isHexNumber(self.current)) then
			if self.current == '.' then
				hasDot = true
			elseif self.current == 'x'  or  self.current == 'X' then
				isHex = true
			end
			self.tokenBuff = self.tokenBuff .. self.current
		    self:next()
        end
	until true
	local sem = {S = self.tokenBuff}
	if hasDot then
		sem.F = tonumber(sem.S)
		if sem.F == nil then
			self:lexErr(err.Error())
		end
		return tkFloat, sem
	end
	sem.I = tonumber(sem.S)
	return tkInteger, sem
end

function LexState:readIdent()
	local last
	local maohao = 0

    -- Point number processing namespace
	while isLetter(self.current)  or  isNumber(self.current)  or  self.current == ':' do
		if isNumber(self.current) and last == ':' then
			self:lexErr("the identification is illegal.")
		end
		last = self.current
		if last == ":" then
		    maohao = maohao + 1
			if maohao > 3 then
				self:lexErr("namespace qualifier:is illegal")
			end
		end
		self.tokenBuff = self.tokenBuff + self.current
		self:next()
	end

	local sem = {S = self.tokenBuff}

	for i = tkDummyKeywordBegin + 1,tkDummyKeywordEnd do 
		if TokenMap[i] == sem.S then
			return i, nil
		end
	end
	for i = tkDummyTypeBegin + 1,i < tkDummyTypeEnd do
		if TokenMap[i] == sem.S then
			return i, nil
		end
	end

	return tkName, sem
end

function LexState:readSharp()
	self:next()
	while isLetter(self.current) do
		self.tokenBuff = self.tokenBuff + elf.current
		self:next()
	end
	if self.tokenBuff ~= "include" then
		self:lexErr("not #include")
	end

	return tkInclude, nil
end

function LexState:readString()
	self:next()
	while true do
		if self.current == EOS then
			self:lexErr("no match")
		elseif self.current == '"' then
			self:next()
			break
		else
			self.tokenBuff.WriteByte(self.current)
			self:next()
		end
	end
	sem.S = self.tokenBuff.String()

	return tkString, sem
end

function LexState:readLongComment()
	while true do
		if self.current == 0 then
			self:lexErr("respect */")
			return
		elseif self.current == '\n'  or  self.current == '\r' then
			self:incLine()
		elseif  self.current == '*' then
			self:next()
			if self.current == 0 then
				return
			elseif self.current == '/' then
				self:next()
				return
			end
		else
			self:next()
		end
	end
end

function LexState:next()
	self.current = self.buff[self.current_index]
end

function LexState:llexDefault()
	if isNumber(self.current) then
		return self:readNumber()
	end
	if isLetter(self.current) then
		return self.readIdent()
	end

	self:lexErr("unrecognized characters, " + tostring(self.current))
	return '0', nil
end

-- Do lexical analysis.
function LexState:llex()
	while true do
		local c = self.current
		if c == EOS then
			return tkEos, nil
		elseif c ==' '  or  c == '\t'  or  c == '\f' or  c == '\v' then
			self:next()
		elseif c == '\n'  or  c == '\r' then
			self:incLine()
		elseif c == '/' then -- Comment processing
			self:next()
			if self.current == '/' then
				while not isNewLine(self.current) and self.current ~= EOS do
					self:next()
				end
			elseif self.current == '*' then
				self:next()
				self:readLongComment()
			else
				self:lexErr("lexical error，/")
			end
		elseif c == '{' then
			self:next()
			return tkBracel, nil
		elseif c == '}' then
			self:next()
			return tkBracer, nil
		elseif c == ';' then
			self:next()
			return tkSemi, nil
		elseif c == '=' then
			self:next()
			return tkEq, nil
		elseif c == '<' then
			self:next()
			return tkShl, nil
		elseif c == '>' then
			self:next()
			return tkShr, nil
		elseif c == ',' then
			self:next()
			return tkComma, nil
		elseif c == '(' then
			self:next()
			return tkPtl, nil
		elseif c == "')'" then
			self:next()
			return tkPtr, nil
		elseif c == '[' then
			self:next()
			return tkSquarel, nil
		elseif c == ']' then
			self:next()
			return tkSquarer, nil
		elseif c == '"' then
			return self.readString()
		elseif c == '#' then
			return self:readSharp()
		else
			return self:llexDefault()
		end
	end
end

-- NextToken return token after lexical analysis.
function LexState:NextToken()
	local T, S = self:llex()
	return {
	    T = T,
		S = S,
		Line = self.linenumber
	}
end

local M = {}

-- NewLexState to update LexState struct.
function M.NewLexState(source, buff)
    return setmetatable({
	    current = ' ',
		linenumber = 1,
		source = source,
		buff = buff,
		tokenBuff = ""
	},LexState)
end

return M
