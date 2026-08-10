--------------------------------------------------------------------------------
-- standard options
--------------------------------------------------------------------------------
vim.opt.shiftwidth        = 2
vim.opt.tabstop           = 2
vim.opt.smartcase         = true
vim.opt.ignorecase        = true
vim.opt.cursorline        = true
vim.opt.number            = true
vim.opt.relativenumber    = true
vim.opt.numberwidth       = 1
vim.opt.clipboard         = "unnamedplus"
vim.opt.expandtab         = true
vim.opt.splitright        = true
vim.opt.splitbelow        = true
vim.opt.updatetime        = 500
vim.opt.conceallevel      = 0
vim.opt.smoothscroll      = true
vim.opt.termguicolors     = true
vim.opt.inccommand        = "split"
vim.opt.virtualedit       = "block"
vim.opt.pumheight         = 10
vim.opt.laststatus        = vim.g.statusline.laststatus
vim.opt.scrolloff         = 2
vim.opt.sidescrolloff     = 2
vim.opt.undofile          = true
vim.opt.confirm           = true
vim.opt.splitkeep         = "screen"
vim.opt.signcolumn        = "yes"

-- -- lists
vim.opt.list              = true

vim.opt.listchars:append "eol:󱞣"
vim.opt.fillchars = {
  -- vert = "▏",
  -- vertleft = "▏",
  -- vertright = "▒",
  -- verthoriz = "▒",
  --
  -- horizup = "🮎",
  -- horizdown = "🮏",

  foldopen = vim.g.symbols.collapse,
  foldsep = " ",
  foldclose = vim.g.symbols.expand,
  fold = " ",
}

-- -- fold options
vim.opt.foldlevel         = 99 -- HACK: to unfold all folds by default
vim.opt.foldexpr          = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldtext          = ""
vim.opt.foldmethod        = "expr"
vim.opt.foldcolumn        = "1"
vim.opt.foldnestmax       = 20 -- default value, probably unnecessary

vim.lsp.log.set_level("off")

-- Nothing in the plugin spec uses the python3 remote provider, but nvim's own
-- ftplugin/python.vim calls has('python3'), which probes each candidate
-- interpreter. python3 is a pyenv shim (~115 ms a call), so that probe added
-- ~400 ms to opening the first .py file of a session.
-- To get :py3 back, pin it instead: vim.g.python3_host_prog = vim.fn.exepath("python3")
vim.g.loaded_python3_provider = 0

-- filetype detection
vim.filetype.add({
  extension = {
    move = "move",
    mvir = "rust",
    norg = "norg",
    cdc = "cadence",
  },
})
