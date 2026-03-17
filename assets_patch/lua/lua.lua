require 'ext.gc'	-- allow __gc for luajit
local ffi = require 'ffi'
local lib = require 'lua.ffi'
local assert = require 'ext.assert'
local class = require 'ext.class'

local xpcallenv = {}
require 'ext.xpcall'(xpcallenv)	-- make sure we have ... forwarding in xpcall
local xpcall = xpcallenv.xpcall

local char_p = ffi.typeof'char*'
local void_p = ffi.typeof'void*'
local void_pp = ffi.typeof'void**'
local size_t_1 = ffi.typeof'size_t[1]'
local uintptr_t = ffi.typeof'uintptr_t'

local Lua = class()

function Lua:init()
	local L = lib.luaL_newstate()
	if not L then error("luaL_newstate failed", 2) end
	self.L = L
	lib.luaL_openlibs(L)

	-- create a default Lua error handler
	self:load[[
return tostring((...)) .. '\n' .. debug.traceback()
]]
	self.errHandlerRef = self:makeref()

	-- create table serialization functions

	local serCode = [[
local b = require 'string.buffer'.new()
local function serTable(x)
	local status, result = pcall(function()
		return b:reset():encode(x):get()
	end)
	if status then return '1'..result end

	local status2, result2 = pcall(function()
		return require 'ext.tolua'(x)
	end)
	if status2 then return '2'..result2 end

	error(tostring(result)..'\n'..tostring(result2))
end
local function deserTable(s)
	local method = s:sub(1,1)
	s = s:sub(2)

	if method == '1' then
		return b:reset():set(s):decode()
	elseif method == '2' then
		return require 'ext.fromlua'(s)
	else
		error("unknown serialization method: "..method)
	end
end
return serTable, deserTable
]]

	-- put a copy of the functions on the parent state
	self.serTable, self.deserTable = assert(load(serCode))()

	-- put a copy of the functions on the child state
	local top = self:gettop()
	self:runAndPush(serCode)
	self.deserTableRef = self:makeref()
	self.serTableRef = self:makeref()
	self:settop(top)

	-- BEGIN PATCH for luajit-android to insert the android asset loader into any newly created Lua states
	do
		local main = ffi.load'main'
		ffi.cdef[[int androidLuajitInitState(void *L);]]
		main.androidLuajitInitState(self.L)

		-- now that the asset loader is setup,
		-- load JNI and set the android JNI as our `require "java"`
		self[=[
local ffi = require 'ffi'
require 'java.ffi.jni'	-- cdef for JNIEnv
ffi.cdef[[JNIEnv * jniEnv;]]
local JNIEnv = require 'java.jnienv'
local main = ffi.load'main'
local J = JNIEnv{
	ptr = main.jniEnv,
	usingAndroidJNI = true,
}
package.loaded.java = J
package.loaded['java.java'] = J
]=]
	end
	-- END PATCH for luajit-android

	-- index access if you don't mind the overhead
	self.global = setmetatable({}, {
		__index = function(t, name)
			return self:globalrw(name)
		end,
		__newindex = function(t, name, value)
			return self:globalrw(name, value)
		end,
	})
end

function Lua:gettop()
	return lib.lua_gettop(self.L)
end

function Lua:makeref()
	return lib.luaL_ref(self.L, lib.LUA_REGISTRYINDEX)
end

function Lua:pushref(ref)
	lib.lua_rawgeti(self.L, lib.LUA_REGISTRYINDEX, ref)
end

function Lua:load(str, name)
	--self:assert(lib.luaL_loadstring(self.L, str))
	self:assert(lib.luaL_loadbuffer(self.L, str, #str, name or str))
end

function Lua:close()
	if self.L then
		lib.lua_close(self.L)
		self.L = nil
	end
end

function Lua:__gc()
	return self:close()
end

function Lua:assert(...)
	local L = self.L
	local errcode = ...
	if not errcode then return ... end
	if errcode == lib.LUA_OK then return ... end
	assert.eq(lib.lua_type(L, -1), lib.LUA_TSTRING)
	local chr = lib.lua_tostring(L, -1)
	local str = ffi.string(chr)
	error(str, errcode)
end

function Lua:pushargs(n, x, ...)
	if n <= 0 then return end
	local L = self.L
	local t = type(x)

	if t == 'nil' then
		lib.lua_pushnil(L)
	elseif t == 'number' then
		lib.lua_pushnumber(L, x)
	elseif t == 'string' then
		lib.lua_pushlstring(L, x, #x)
	elseif t == 'boolean' then
		lib.lua_pushboolean(L, x and 1 or 0)
	elseif t == 'function' then
		local str = string.dump(x)
		self:load(str, 'Lua:pushargs function')
	--elseif t == 'thread' then
	--	is it possible?
	elseif t == 'table' then

		local s = self.serTable(x)
		self:pushref(self.deserTableRef)
		lib.lua_pushlstring(L, ffi.cast(char_p, s), #s)
		lib.lua_pcall(L, 1, 1, 0)

	elseif t == 'cdata' then
		-- can I do lua_topointer on whatever state is giving us 'x' ?
		-- if I can get a hold of its state ...
		-- otherwise ...
		-- cheap trick, cast to intptr, then to ULL, then serialize
		local typename = tostring(ffi.typeof(x)):match'^ctype<(.*)>$'
		local ptr = ffi.cast(void_p, x)
		local uintptr = ffi.cast(uintptr_t, ptr)
		local strintptr
		-- tostring(int32_t) produces the string "cdata<int> ...", while tostring(int64_t) produces a serializable number with LL suffix
		if ffi.sizeof(uintptr_t) == 4 then
			strintptr = '0x'..bit.tohex(uintptr, 8)
		else
			-- is a uint64_t and should serialize to number..ULL
			strintptr = tostring(uintptr)
		end
		-- what are the promises that the intepreted code will maintain all bits of precision?
		-- should I be encoding it and decoding it both one byte at a time?
		self:runAndPush([[
local ffi = require 'ffi'

local result = ffi.cast('void*', ]]..strintptr..[[)

]]..(typename and
	[[
result = ffi.cast(']]..typename..[[', result)
]] or '')
..[[

return result
]])
		-- assert the 2nd from the top is the error handler
		lib.lua_remove(L, -2)
	else
		print('WARNING: idk how to push '..t)
		lib.lua_pushnil(L)
	end

	return self:pushargs(n-1, ...)
end

-- get stack location as bool
function Lua:getboolean(i)
	return 0 ~= lib.lua_toboolean(self.L, i)
end

function Lua:getpointer(i)
	return lib.lua_topointer(self.L, i)
end

function Lua:getnumber(i)
	return lib.lua_tonumber(self.L, i)
end

-- get stack location as string
function Lua:getstring(i)
	local len = size_t_1()
	local ptr = lib.lua_tolstring(self.L, i, len)
	return ptr ~= nil and ffi.string(ptr, len[0]) or nil
end

function Lua:gettable(i)
	local L = self.L

	self:pushref(self.serTableRef)
	lib.lua_pushvalue(L, i)
	lib.lua_pcall(L, 1, 1, 0)
	local s = self:getstring(-1)
	return self.deserTable(s)
end

function Lua:getfunction(i)
	local L = self.L
	-- same trick as above? string.dump and reload?
	self:pushref(self.errHandlerRef)
	local errHandlerLoc = self:gettop()		-- errHandler
	lib.lua_getglobal(L, 'string')			-- errHandler, string
	lib.lua_getfield(L, -1, 'dump')			-- errhandler, string, dump
	lib.lua_remove(L, -2)					-- errHandler, dump
	lib.lua_pushvalue(L, i)					-- errHandler, dump, i
	self:assert(lib.lua_pcall(L, 1, 1, errHandlerLoc))	-- result
	local data = self:getstring(-1)
	lib.lua_pop(L, 1)
	return load(data)
end

function Lua:getcdata(i)
-- this gets me via thread lib:
-- "bad argument #3 to 'pthread_create' (cannot convert 'void *(*)()' to 'void *(*)()')"
-- maybe due to luajit creation of closures?
--[=[
	local L = self.L
	-- get the ctype ... lazy way being via lua load
	self:pushref(self.errHandlerRef)
	local errHandlerLoc = self:gettop()

	self:load[[
return tostring(require 'ffi'.typeof((...))):match'^ctype<(.*)>$'
]]
	lib.lua_pushvalue(L, i)
	self:assert(lib.lua_pcall(L, 1, 1, errHandlerLoc))
	-- result is now errHandler, ctype-as-str

	local ctypestr = self:getstring(-1)
	lib.lua_pop(L, 2)
--]=]
-- [=[
	local ctypestr
--]=]

	local ptr = lib.lua_topointer(self.L, i)
	-- I guess all LuaJIT cdata's hold ... pointers ... ? always?
	-- I suspect this can get me into trouble:
	local result = ffi.cast(void_pp, ptr)
	if result == nil then return nil end
	result = result[0]
	if ctypestr then
		result = ffi.cast(ctypestr, result)
	end
	return result
end

-- get stack location
function Lua:getstack(i)
	local L = self.L
	local luatype = lib.lua_type(L, i)
	if luatype == lib.LUA_TNONE
	or luatype == lib.LUA_TNIL
	then
		-- it's already nil
	elseif luatype == lib.LUA_TBOOLEAN then
		return self:getboolean(i)
	elseif luatype == lib.LUA_TLIGHTUSERDATA then
		return self:getpointer(i)	-- is this ok?
	elseif luatype == lib.LUA_TNUMBER then
		return self:getnumber(i)
	elseif luatype == lib.LUA_TSTRING then
		return self:getstring(i)
	elseif luatype == lib.LUA_TTABLE then
		return self:gettable(i)
	elseif luatype == lib.LUA_TFUNCTION then
		return self:getfunction(i)
	--elseif luatype == lib.LUA_TUSERDATA then
		-- return a string binary-blob of the data?
	--elseif luatype == lib.LUA_TTHREAD
	--elseif luatype == lib.TPROTO
	elseif luatype == lib.LUA_TCDATA then
		return self:getcdata(i)
	else
		print("WARNING: idk how to pop "..tostring(luatype))
		return nil
	end
end

-- pop args from stack, convert them, and return them
function Lua:popargs(n, i)
	if n <= 0 then return end
	-- how are args evaluated? left-to-right?
	local result = self:getstack(i)
	return result, self:popargs(n-1, i+1)
end

-- read/write a global
function Lua:globalrw(name, ...)
	local L = self.L
	if select('#', ...) > 0 then
		-- write a global
		self:pushargs(1, (...))
		lib.lua_setglobal(L, name)
	else
		-- read a global
		local top = self:gettop()
		lib.lua_getglobal(L, name)
		return self:settop(top, self:popargs(1, self:gettop()))
	end
end

function Lua:settop(top, ...)
	lib.lua_settop(self.L, top)
	return ...
end

-- runs `code`
-- accepts Lua args
-- but leaves results on the stack
-- also leaves the error handler on the stack under them
function Lua:runAndPush(code, ...)
	local L = self.L

	-- push error handler first
	self:pushref(self.errHandlerRef)
	local errHandlerLoc = self:gettop()

	-- push function next
	self:load(code)

	-- push args next
	-- this is a serialize-deserialize layer to ensure that whatever is passed through changes to the new Lua state
	local n = select('#', ...)
	self:pushargs(n, ...)

	self:assert(lib.lua_pcall(L, n, lib.LUA_MULTRET, errHandlerLoc))
end

-- this is very specific to pureffi/threads.lua's "threads.new" function
-- loads 'code' in the enclosed Lua state
-- serializes and passes any args into 'code's function
-- calls the function
-- returns the results, cast as a uintptr_t*
function Lua:run(code, ...)
	local top = self:gettop()
	local result, err = xpcall(function(...)
		self:runAndPush(code, ...)
	end, nil, ...)
	if not result then
		self:settop(top)
		error(err)
	end
	local newtop = self:gettop()

	-- convert args on stack, reset top, and return converted args
	return self:settop(top, self:popargs(newtop - (top+1), top+2))
end

function Lua:__call(code, ...)
	return self:run(code, ...)
end

return Lua
