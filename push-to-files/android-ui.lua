-- this is a lot like android-launch.lua
-- TODO the stdout redirect ONLY NEEDS TO HAPPEN ONCE PER PROCESS
-- that means only once between android-ui.lua and android-launch.lua
xpcall(function(...)
	local ffi = require 'ffi'

	-- first chdir to our lua projects root
	ffi.cdef[[int chdir(const char *path);]]
	local function chdir(s)
		local res = ffi.C.chdir((assert(s)))
		assert(res==0, 'chdir '..tostring(s)..' failed')
	end

	local appFilesDir = os.getenv'APP_FILES_DIR'
	--local appFilesDir = '/data/data/io.github.thenumbernine.SDLLuaJIT/files'
	-- in Termux I've got this set to $LUA_PROJECT_PATH env var,
	-- but in JNI, no such variables, and barely even env var access to what is there.
	-- [[ running on sdcard
	local projectDir = '/sdcard/Documents/Projects/lua'
	local startDir = projectDir
	--]]
	--[[ running on files/
	local projectDir = appFilesDir
	local startDir = projectDir
	--]]

	chdir(startDir)

	-- next redirect stdout and stderr to ./out.txt
	ffi.cdef[[
struct FILE;
typedef struct FILE FILE;
FILE * freopen(const char * filename, const char * modes, FILE * stream);
extern FILE * stdin;
extern FILE * stdout;
extern FILE * stderr;
]]
	local newstdoutfn = 'out.txt'	-- relative to cwd
	ffi.C.freopen(newstdoutfn, 'w+', ffi.C.stdout)
	ffi.C.freopen(newstdoutfn, 'w+', ffi.C.stderr)
	io.stdout:flush()
	io.stderr:flush()
	io.output(io.stdout)	-- I thought doing this would help io.flush() work right but meh
	-- if we error before this point then we won't see it anyways

	-- [[ old print doesn't flush new stdout ?
	local oldprint = print
	print = function(...)
		oldprint(...)
		io.flush()
	end
	--]]

	print'BEGIN android-ui.lua'

	-- setup LUA_PATH and LUA_CPATH here
	package.path = table.concat({
		'./?.lua',
		projectDir..'/?.lua',
		projectDir..'/?/?.lua',
	}, ';')
	package.cpath = table.concat({
		'./?.so',
		projectDir..'/?.so',
		projectDir..'/?/init.so',
	}, ';')

	ffi.cdef[[int setenv(const char*,const char*,int);]]
	-- let subsequent invoked lua processes know where to find things
	ffi.C.setenv('LUA_PATH', package.path, 1)
	ffi.C.setenv('LUA_CPATH', package.cpath, 1)

	--hot take: it should be "Android"
	if ffi.os == 'Linux' then ffi.os = 'Android' end

	print('android-ui run with:', ...)
	local msg = ...
	if msg == 'init' then
		local androidEnv = require 'android-setup'
	end

end, function(err)
	print(err, '\n', debug.traceback())
end, ...)

-- need this or else we will lose output.
io.stdout:flush()
io.stderr:flush()
print'DONE android-ui.lua'
io.stdout:flush()
