xpcall(function(...)
	local ffi = require 'ffi'

	-- chdir to our lua projects root
	ffi.cdef[[int chdir(const char *path);]]
	local function chdir(s)
		local res = ffi.C.chdir((assert(s)))
		assert(res==0, 'chdir '..tostring(s)..' failed')
	end

	local projectDir = '/sdcard/Documents/Projects/lua'
	chdir(projectDir)

	-- redirect stdout and stderr to ./out.txt
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

	print'BEGIN android main.lua'

	--hot take: it should be "Android"
	if ffi.os == 'Linux' then ffi.os = 'Android' end

	-- TODO here ... setup the package.loader from the luajit -> java functions
	assert(loadfile'luajit-android.lua')(...)

	print('android main run with:', ...)
	local msg = ...
	if msg == 'init' then
		--local androidEnv = require 'android-setup'
	end
end, function(err)
	print(err, '\n', debug.traceback())
end, ...)

-- need this or else we will lose output.
io.stdout:flush()
io.stderr:flush()
print'DONE android main.lua'
io.stdout:flush()
