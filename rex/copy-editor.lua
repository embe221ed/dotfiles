-- Minimal Neovim init used only by Rex's floating copy viewer.
local settings = assert(vim.g.rex_copy, "Missing Rex copy mode settings")
vim.opt.loadplugins = false
vim.opt.modeline = false
vim.opt.exrc = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shadafile = "NONE"
vim.opt.clipboard = "" -- Never read the clipboard or probe external providers.
vim.opt.mouse = ""
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.signcolumn = "no"
vim.opt.wrap = true
vim.opt.scrolloff = 0
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true
vim.opt.termguicolors = false
vim.opt.laststatus = 2
vim.opt.statusline = " Copy  v/V/Ctrl-v select  y/Enter copy  q close%=%l/%L "
vim.api.nvim_set_hl(0, "Normal", {})
vim.api.nvim_set_hl(0, "Visual", { reverse = true })
vim.api.nvim_set_hl(0, "StatusLine", { reverse = true })

local function remove_capture() vim.fn.delete(settings.path) end
vim.api.nvim_create_autocmd("BufReadPost", {
  once = true,
  callback = function()
    -- Keep the snapshot only in memory once loaded; never retain terminal
    -- history in a swap file, ShaDa, backup, or a temporary file after exit.
    remove_capture()
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.modifiable = false
    vim.bo.readonly = true
  end,
})
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local line = vim.api.nvim_buf_line_count(0)
    while line > 1 and vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1] == "" do
      line = line - 1
    end
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd("normal! zb")
  end,
})

-- Vim performs the selection, including word motions, lines and rectangles.
-- Local Mac copies finish through pbcopy before closing; other connections
-- use OSC 52 to send the result to the Rex app rather than a remote clipboard.
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    if vim.v.event.operator ~= "y" then return end
    local text = vim.fn.getreg(vim.v.event.regname)
    local ok, err = pcall(function()
      if settings.clipboard then
        local result = vim.system({ settings.clipboard }, { stdin = text }):wait()
        assert(result.code == 0, result.stderr or "Clipboard copy failed")
      else
        require("vim.ui.clipboard.osc52").copy("+")(vim.split(text, "\n", { plain = true }))
      end
    end)
    if not ok then
      local message = tostring(err):gsub("^.-:%d+: ", "")
        :gsub("[%z\1-\31\127]", " "):gsub("%%", "%%%%")
      -- Keep the buffer open without a hit-Enter prompt swallowing q/Escape.
      vim.schedule(function() vim.opt.statusline = " Copy failed: %<" .. message .. "%= q close " end)
      return
    end
    vim.schedule(function() vim.cmd("qa!") end)
  end,
})
vim.keymap.set("x", "<CR>", "y")
vim.keymap.set("n", "<CR>", "yy")
vim.keymap.set({ "n", "x" }, "q", "<Cmd>qa!<CR>")
vim.keymap.set("n", "<Esc>", "<Cmd>qa!<CR>")
vim.keymap.set({ "n", "x" }, "<C-c>", "<Cmd>qa!<CR>")

vim.api.nvim_create_autocmd("VimLeavePre", {
  once = true,
  callback = function()
    remove_capture()
    -- Closing a float restores its previous layer natively. Only opening from
    -- a zoomed pane needs one extra callback to restore the saved zoom.
    if settings.restore then
      vim.fn.system({ settings.restore, "--autostart=false", "--color=never",
        "--timeout=2s", "do", "tmux_copy_restore" })
    end
  end,
})
