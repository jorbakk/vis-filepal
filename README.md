# The filepal vis plugin

Filepal helps with managing everything related to file buffers and paths in [vis](https://github.com/martanne/vis). Currently, it can:

- Remember the cursor position for each file that has been opened. Cursor positions are updated on window open and close events, and not when quitting vis, so they are already available during a running vis session (and for all vis instances).
- Provide a local and global file history. The global file history shows all the files that were most recently used by one user up to `history` count files. The local history does the same for files opened in the current instance of vis. The file history is shown using `vis-menu` by default. For configurable parameters, see [Configuration](#configuration) below.
- Show a warning message, if a file is already open in another instance of vis.
- Make a substring-search in all files that have been opened so far

## Usage

In vis:

`:ff` shows global file history

`:fl` shows local file history

`:fs <search_string>` search in global file history

## Requirements

Currently filepal requires the [lua bindings](https://lua.sqlite.org/) for `SQLite3`, which are also available in luarocks.

The process id is fetched using the Linux proc filesystem. Alternatively, the luarocks package `getpid` could be used, which uses the Posix `getpid()` C function call. A more portable solution is yet to be done.

## Configuration

In visrc.lua:

```lua
plugin_vis_filepal = require('plugins/vis-filepal')

-- Path to the vis-menu executable (default: "vis-menu")
plugin_vis_filepal.vis_menu_path = "vis-menu"

-- Arguments passed to vis-menu (default: "-l 10")
plugin_vis_filepal.vis_menu_args = "-l 10"

-- File path to file history (default: "$HOME/.vis.db") 
plugin_vis_filepal.dbpath = os.getenv("HOME") .. "/.vis.db"

-- The number of most recently used files shown in the menu (default: 100)
plugin_vis_filepal.history = 100

-- Files to exclude based on substring matching, default:
plugin_vis_filepal.ignore = {
	"COMMIT_EDITMSG$",
	"git%-rebase%-todo$",
}

-- Mapping configuration example (<Space>f and <Space>l)
vis.events.subscribe(vis.events.INIT, function()
    vis:map(vis.modes.NORMAL, " f", ":ff<Enter>", "most recently used files")
    vis:map(vis.modes.NORMAL, " l", ":fl<Enter>", "most recently used local files")
end)
```

