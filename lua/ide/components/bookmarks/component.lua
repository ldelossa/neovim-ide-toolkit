local base = require('ide.panels.component')
local commands = require('ide.components.bookmarks.commands')
local logger = require('ide.logger.logger')
local diff_buf = require('ide.buffers.diffbuffer')
local libwin = require('ide.lib.win')
local libbuf = require('ide.lib.buf')
local bookmarknode = require('ide.components.bookmarks.bookmarknode')
local icon_set = require('ide.icons').global_icon_set
local notebook = require('ide.components.bookmarks.notebook')

BookmarksComponent = {}

BookmarksComponent.NotebooksPath = "~/.config/nvim/bookmarks"

local config_prototype = {
    disabled_keymaps = false,
    keymaps = {
        expand = "zo",
        collapse = "zc",
        collapse_all = "zM",
        jump = "<CR>",
        jump_tab = "t",
        hide = "<C-[>",
        close = "X",
        maximize = "+",
        minimize = "-"
    },
}

-- BookmarksComponent is a derived @Component implementing a file explorer.
-- Must implement:
--  @Component.open
--  @Component.post_win_create
--  @Component.close
--  @Component.get_commands
BookmarksComponent.new = function(name, config)
    -- extends 'ide.panels.Component' fields.
    local self = base.new(name)

    -- a logger that will be used across this class and its base class methods.
    self.logger = logger.new("bookmarks")

    self.config = vim.deepcopy(config_prototype)

    self.hidden = true

    -- the currently opened notebook containing bookmarks
    self.notebook = nil

    local function setup_buffer()
        local log = self.logger.logger_from(nil, "Component._setup_buffer")
        local buf = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
        vim.api.nvim_buf_set_option(buf, 'filetype', 'filetree')
        vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
        vim.api.nvim_buf_set_option(buf, 'modifiable', false)
        vim.api.nvim_buf_set_option(buf, 'swapfile', false)
        vim.api.nvim_buf_set_option(buf, 'textwidth', 0)
        vim.api.nvim_buf_set_option(buf, 'wrapmargin', 0)

        if not self.config.disable_keymaps then
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.expand, "", {silent=true, callback=function() self.expand() end})
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.collapse, "", {silent=true, callback=function() self.collapse() end})
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.collapse_all, "",{silent=true, callback=function() self.collapse_all() end})
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.jump, "", {silent=true, callback=function() self.jump_bookmarknode({fargs={}}) end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.jump_tab, "", {silent=true, callback=function() self.jump_bookmarknode({fargs={"tab"}}) end })
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.hide, "", {silent=true, callback=function() self.hide() end})
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.maximize, "", {silent=true, callback=self.maximize})
            vim.api.nvim_buf_set_keymap(buf, "n", self.config.keymaps.minimize, "", {silent=true, callback=self.minimize})
        end

        return buf
    end

    self.buf = setup_buffer()

    -- implements @Component.open()
    function self.open()
        return self.buf
    end

    -- implements @Component interface
    function self.post_win_create()
        local log = self.logger.logger_from(nil, "Component.post_win_create")
        icon_set.set_win_highlights()
    end

    function self.expand(args)
        local log = self.logger.logger_from(nil, "Component.expand")
        if not libwin.win_is_valid(self.win) then
            return
        end
        local node = self.notebook.tree.unmarshal(self.state["cursor"].cursor[1])
        if node == nil then
            return
        end
        self.notebook.tree.expand_node(node)
        self.notebook.tree.marshal({no_guides_leaf = true})
        self.state["cursor"].restore()
    end

    function self.collapse(args)
        local log = self.logger.logger_from(nil, "Component.collapse")
        if not libwin.win_is_valid(self.win) then
            return
        end
        local node = self.notebook.tree.unmarshal(self.state["cursor"].cursor[1])
        if node == nil then
            return
        end
        self.notebook.tree.collapse_node(node)
        self.notebook.tree.marshal({no_guides_leaf = true})
        self.state["cursor"].restore()
    end

    function self.collapse_all(args)
        local log = self.logger.logger_from(nil, "Component.collapse_all")
        if not libwin.win_is_valid(self.win) then
            return
        end
        local node = self.notebook.tree.unmarshal(self.state["cursor"].cursor[1])
        if node == nil then
            return
        end
        self.notebook.tree.collapse_subtree(self.notebook.tree.root)
        self.notebook.tree.marshal({no_guides_leaf = true})
        self.state["cursor"].restore()
    end

    function self.jump_bookmarknode(args)
        log = self.logger.logger_from(nil, "Component.jump_bookmarknode")

        local node = self.notebook.tree.unmarshal(self.state["cursor"].cursor[1])
        if node == nil then
            print("nope")
            return
        end

        local tab = false
        for _, arg in ipairs(args.fargs) do
            if arg == "tab" then
                tab = true
            end
        end

        local win = self.workspace.get_win()

        if tab then
            vim.cmd("tabnew")
        end
    end

    function self.get_commands()
        local log = self.logger.logger_from(nil, "Component.get_commands")
        return commands.new(self).get()
    end

    -- notebook functions --

    local function _get_notebooks_dir()
        local project_dir = vim.fn.getcwd()
        local project_sha = vim.fn.sha256(project_dir)
        local notebook_dir = vim.fn.fnamemodify(BookmarksComponent.NotebooksPath, ":p") .. "/" .. project_sha
        local exists = false
        if vim.fn.isdirectory(notebook_dir) ~= 0 then
            exists = true
        end
        return notebook_dir, exists
    end

    local function _ls_notebooks()
        local notebooks_dir, exists = _get_notebooks_dir()
        if not exists then
            return {}
        end
        local notebooks = vim.fn.readdir(notebooks_dir)
        return notebooks
    end

    function self.remove_notebook(args)
        local notebooks = _ls_notebooks()
        local on_choice = function(item)
        end
        vim.ui.select(
            notebooks,
            {
                prompt = "Select a notebook to open: ",
                format_item = function(item)
                    return vim.fn.fnamemodify(item, ":r")
                end
            },
            on_choice
        )
    end

    function self.test(args)
    end

    function self.open_notebook(args)
        local notebooks = _ls_notebooks()
        local on_choice = function(item)
            local notebooks_dir = _get_notebooks_dir()
            local notebook_file = notebooks_dir .. "/" .. item
            local name = vim.fn.fnamemodify(item, ":t")
            if self.notebook ~= nil then
                self.notebook.close()
            end
            self.notebook = notebook.new(self.buf, name, notebook_file)
            self.focus()
        end
        vim.ui.select(
            notebooks,
            {
                prompt = "Select a notebook to open: ",
                format_item = function(item)
                    return vim.fn.fnamemodify(item, ":r")
                end
            },
            on_choice
        )
    end

    function self.create_notebook(args)
        local on_confirm = function(input)
            if input == nil or input == "" then
                return
            end
            -- get notebook directory for current project, create if not exists.
            local notebook_dir, exists = _get_notebooks_dir()
            if not exists then
                vim.fn.mkdir(notebook_dir)
            end
            -- create notebook file
            local notebook_file = notebook_dir .. "/" .. input
            print(notebook_file)
            vim.fn.mkdir(notebook_file)
        end
        vim.ui.input({
            prompt = "Name this notebook: "
        }, on_confirm)
    end

    -- bookmark functions --

    function self.create_bookmark(args)
        if self.notebook == nil then
            vim.notify("A notebook must be opened first.", vim.log.levels.Error)
            return
        end
        self.notebook.create_bookmark(args)
    end

    function self.remove_bookmark(args)
        if self.notebook == nil then
            vim.notify("A notebook must be opened first.", vim.log.levels.Error)
            return
        end
        local node = self.notebook.tree.unmarshal(self.state["cursor"].cursor[1])
        if node == nil then
            return
        end
        self.notebook.remove_bookmark(node.key)
    end

    return self
end

return BookmarksComponent
