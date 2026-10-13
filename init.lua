--- Copyright (C) 2026  Jörg Bakker
---
-- luacheck: globals vis

local M = {}
local db
local STATUS_OPEN   = "open"
local STATUS_CLOSED = "closed"

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


local function is_file_ignored(path)
	for _, pattern in pairs(M.ignore) do
		if path:match(pattern) then
			return true
		end
	end
	return false
end


local function on_init()
	db = sqlite3.open(M.dbpath)
	db:exec([[
	  create table if not exists file
	  (idx integer, path text, time integer, curpos integer, line integer,
	   col integer, vppos integer)
	]])
	db:exec([[
	  create index if not exists fidx_idx on file (idx);
	  create index if not exists path_idx on file (path);
	  create index if not exists time_idx on file (time);
	]])
	db:exec([[
	  create table if not exists proc
	  (idx integer, pid integer, status text)
	]])
	db:exec([[
	  create index if not exists pidx_idx on proc (idx);
	  create index if not exists pid_idx  on proc (pid);
	]])
end


local function on_quit()
	local pid = get_pid()
	local sql = string.format([[
	  delete from proc where pid = %d
	]], pid)
	db:exec(sql)
	db:close()
end


--- Returning true in update() means that nothing is done afterwards, i.e. no insert
--- of a new entry in the file table.
local function update(win, status)
	local ret = false

	local sql = string.format([[
	  update file
	  set time = %d, curpos = %d, line = %d, col = %d, vppos = %d
	  where path = '%s'
	]],
	  os.time(),
	  win.selection.pos,
	  win.selection.line, win.selection.col,
	  win.viewport.bytes.start,
	  win.file.path)
	--- Do nothing, if the statement fails e.g. of database being locked, the entries
	--- for one file would pile up. I could check for different error conditions ...
	if db:exec(sql) ~= sqlite3.OK then return true end

	if db:changes() > 0 then
		local pid = get_pid()
		--- Check if file is open in more than one window then stop here and do nothing
		local wcnt = 0
		for w in vis:windows() do
			if w.file.path == win.file.path then wcnt = wcnt + 1 end
		end
		if wcnt > 1 then return true end
		sql = string.format([[
		  update proc as p
		  set status = '%s'
		  from file as f
		  where f.idx = p.idx and p.pid = %d and f.path = '%s'
		]],
		  status, pid, win.file.path)
		if db:exec(sql) ~= sqlite3.OK then return true end
		if db:changes() > 0 then return true
		else
			sql = string.format([[
			  insert into proc (idx, pid, status)
			  select f.idx, %d, '%s'
			  from file as f
			  where f.path = '%s'
			]],
			  pid, status,
			  win.file.path)
			if db:exec(sql) ~= sqlite3.OK then return true end
			if db:changes() > 0 then return true end
		end
	end
	return ret
end


local function insert(win, status)
	local idx
	local sql = string.format([[
	  select idx from file order by idx desc limit 1
	]], win.file.path)
	for i in db:urows(sql) do idx = i + 1 end

	sql = string.format([[
	  insert into file (idx, path, time, curpos, line, col, vppos)
	  values (%d, '%s', %d, %d, %d, %d, %d)
	]],
	  idx,
	  win.file.path,
	  os.time(),
	  win.selection.pos,
	  win.selection.line,
	  win.selection.col,
	  win.viewport.bytes.start)
	db:exec(sql)

	local pid = get_pid()
	sql = string.format([[
	  insert into proc (idx, pid, status)
	  values (%d, %d, '%s')
	]], idx, pid, status)
	db:exec(sql)
end


local function check_file_path(win)
	if win.file == nil or win.file.path == nil then
		return false
	end
	if is_file_ignored(win.file.path) then
		return false
	end
	return true
end


local function on_win_open(win)
	if not check_file_path(win) then return end

	local pid = get_pid()
	local sql = string.format([[
	  select p.pid, p.status
	  from file as f, proc as p
	  where f.idx = p.idx and f.path = '%s' and p.pid <> %d
	  order by f.time desc limit 1
	]], win.file.path, pid)
	for file_pid, file_status in db:urows(sql) do
		if file_pid ~= nil and file_pid > 0 and file_status == STATUS_OPEN then
			vis:info(string.format("file '%s' already open in vis instance with pid: %d",
			  win.file.path, file_pid))
		end
	end

	sql = string.format([[
	  select curpos, vppos from file where path = '%s' limit 1
	]], win.file.path)
	for curpos, _ in db:urows(sql) do
		if curpos == nil then
			insert(win, STATUS_OPEN)
		else
			win.selection.pos = curpos
			vis:feedkeys("zz")
			update(win, STATUS_OPEN)
		end
	end
end


local function on_win_close(win)
	if not check_file_path(win) then return end

	if not update(win, STATUS_CLOSED) then
		insert(win, STATUS_CLOSED)
	end
end


local function show_file_list(sql)
	local file_list = {}
	for fnames in db:urows(sql) do
		table.insert(file_list, fnames)
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
	  select path from file
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
	  select path from file as f, proc as p
	  where f.idx = p.idx and p.pid = %d and f.path <> '%s'
	  order by time desc
	  limit %d
	]], pid, win.file.path, M.history)

	show_file_list(sql)
	return true;
end)


vis:command_register("fs", function(argv, _force, win, _selection, _range)
	local sql = string.format([[
	  select path from file
	  where path <> '%s' and path like '%%%s%%'
	  order by time desc
	  limit %d
	]], win.file.path, argv[1], M.history)

	show_file_list(sql)
	return true;
end)


--- win open / close events are triggered on file changes,
--- even if the window doesn't change. The only situation
--- when file events and win events aren't triggered pair-wise
--- is, when there is more than one window with the same file
--- open in the same vis process.

vis.events.subscribe(vis.events.INIT,       on_init)
vis.events.subscribe(vis.events.WIN_OPEN,   on_win_open)
vis.events.subscribe(vis.events.WIN_CLOSE,  on_win_close)
vis.events.subscribe(vis.events.QUIT,       on_quit)

return M

