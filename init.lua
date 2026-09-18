--- Copyright (C) 2026  Jörg Bakker
---
-- luacheck: globals vis

local M = {}
local db

local sqlite3 = require("lsqlite3complete")
M.dbpath = os.getenv("HOME") .. "/.vis.db"
M.ignore = {
	"COMMIT_EDITMSG$",
	"git%-rebase%-todo$",
}
M.vis_menu_path = "vis-menu"
M.vis_menu_args = "-l 10"
M.history = 100


local function get_pid()
	local proc = io.open("/proc/self/stat", "r")
	local pid = proc:read("n")
	proc:close()
	return pid or 0
end


local is_file_ignored = function(path)
	for _, pattern in pairs(M.ignore) do
		if path:match(pattern) then
			return true
		end
	end
	return false
end


local on_init = function()
	db = sqlite3.open(M.dbpath)
	db:exec([[
	  create table if not exists file (path, time, curpos, line, col, vppos, pid)
	]])
	db:exec([[
	  create index if not exists path_idx on file (path);
	  create index if not exists time_idx on file (time);
	  create index if not exists pid_idx  on file (pid);
	]])
end


local on_quit = function()
	local pid = get_pid()
	local sql = string.format([[
	  update file set pid = 0 where pid = %d
	]], pid)
	db:exec(sql)
	db:close()
end


local function update(win)
	local pid = get_pid()
	local sql = string.format([[
	  update file
	  set time = %d, curpos = %d, line = %d, col = %d, vppos = %d, pid = %d
	  where path = '%s'
	]],
	  os.time(),
	  win.selection.pos,
	  win.selection.line, win.selection.col,
	  win.viewport.bytes.start, pid,
	  win.file.path)
	db:exec(sql)
	return db:changes() > 0
end


local function insert(win)
	local pid = get_pid()
	local sql = string.format([[
	  insert into file (path, time, curpos, line, col, vppos, pid)
	  values ('%s', %d, %d, %d, %d, %d, %d)
	]],
	  win.file.path, os.time(),
	  win.selection.pos,
	  win.selection.line, win.selection.col,
	  win.viewport.bytes.start, pid)
	db:exec(sql)
end


local on_file_open = function(file)
	local pid = get_pid()
	local sql = string.format([[
	  select pid from file where path = '%s'
	]], file.path)
	local iter, state, initial = db:urows(sql)
	local file_pid = iter(state, initial)
	if file_pid ~= nil and file_pid > 0 and file_pid ~= pid then
		vis:info(string.format("file '%s' already open in vis instance with pid: %d",
		  file.path, file_pid))
	end
end


local on_win_open = function(win)
	if win.file == nil or win.file.path == nil then
		return
	end
	if is_file_ignored(win.file.path) then
		return
	end
	local sql = string.format([[
	  select curpos, vppos, pid from file where path = '%s'
	]], win.file.path)
	local iter, state, initial = db:urows(sql)
	local curpos, _, _ = iter(state, initial)
	if curpos == nil then
		insert(win)
	else
		win.selection.pos = curpos
		vis:feedkeys("zz")
		update(win)
	end
end


local on_win_close = function(win)
	if win.file == nil or win.file.path == nil then
		return
	end
	if is_file_ignored(win.file.path) then
		return
	end
	if not update(win) then
		insert(win)
	end
end


local function show_file_list(sql)
	local file_list = {}
	for f in db:urows(sql) do
		table.insert(file_list, f)
	end
	local command = M.vis_menu_path .. " " .. M.vis_menu_args
	local status, output, _ = vis:pipe(table.concat(file_list, '\n'), command)
	if status == 0 then
		--- Remove trailing newline
		vis:command(string.format("e '%s'", output:sub(1, -2)))
	end
	vis:redraw()
end


vis:command_register("ff", function(_argv, _force, win, _selection, _range)
	local sql = string.format([[
	  select path
	  from file
	  where path <> '%s'
	  order by time desc
	  limit %d
	]], win.file.path, M.history)
	show_file_list(sql)
	return true;
end)


vis:command_register("fl", function(_argv, _force, win, _selection, _range)
	local pid = get_pid()
	local sql = string.format([[
	  select path
	  from file
	  where pid = %d and path <> '%s'
	  order by time desc
	  limit %d
	]], pid, win.file.path, M.history)
	show_file_list(sql)
	return true;
end)


vis:command_register("fs", function(argv, _force, win, _selection, _range)
	local sql = string.format([[
	  select path
	  from file
	  where path <> '%s' and path like '%%%s%%'
	  order by time desc
	  limit %d
	]], win.file.path, argv[1], M.history)
	show_file_list(sql)
	return true;
end)


vis.events.subscribe(vis.events.INIT, on_init)
vis.events.subscribe(vis.events.FILE_OPEN, on_file_open)
vis.events.subscribe(vis.events.WIN_OPEN, on_win_open)
vis.events.subscribe(vis.events.WIN_CLOSE, on_win_close)
vis.events.subscribe(vis.events.QUIT, on_quit)

return M

