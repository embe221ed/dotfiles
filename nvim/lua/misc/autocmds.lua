local api = vim.api
local group = api.nvim_create_augroup("user_autocmds", { clear = true })

api.nvim_create_autocmd(
  "FileType",
  {
    group     = group,
    desc      = "enable spellcheck for markdown and norg files, set indentation to 4 spaces",
    pattern   = { "markdown", "txt", "norg" },
    callback  = function()
      vim.bo.shiftwidth  = 4
      vim.bo.tabstop     = 4
      -- vim.wo[0][0] is the BUFFER-scoped window option. Plain vim.wo sets the
      -- window value, which then leaks onto the next buffer shown in this window.
      vim.wo[0][0].conceallevel = 2
      -- Check if current window is floating
      local win_config = api.nvim_win_get_config(0)
      local is_floating = win_config.relative ~= ""
      local is_special_buffer = vim.bo.buftype ~= ""

      -- Only enable spellcheck if not in a floating window
      if not is_floating and not is_special_buffer then
        vim.wo[0][0].spell = true
        vim.bo.spelllang = "en_us"
      end
    end,
  }
)

api.nvim_create_autocmd(
  "FileType",
  {
    group     = group,
    desc      = "disable diagnostics in the Lazy UI buffer",
    pattern   = { "lazy" },
    -- vim.diagnostic.config() with no namespace mutates the GLOBAL config and is
    -- never restored, so one :Lazy used to kill virtual_lines everywhere for the
    -- rest of the session. Scope the suppression to the buffer that fired.
    callback  = function(args)
      vim.diagnostic.enable(false, { bufnr = args.buf })
    end,
  }
)

api.nvim_create_autocmd(
  "FileType",
  {
    group     = group,
    desc      = "set some options for move files",
    pattern   = { "move" },
    callback  = function()
      vim.bo.commentstring = "// %s"
    end,
  }
)

api.nvim_create_autocmd(
  "TermOpen",
  {
    group     = group,
    desc      = "do not show line numbers in terminal buffer",
    pattern   = { "*" },
    callback  = function()
      vim.wo.number = false
      vim.wo.relativenumber = false
    end,
  }
)

api.nvim_create_autocmd(
  "User",
  {
    group     = group,
    desc      = "ensure that special buffers are closed before saving the session",
    pattern   = "PersistenceSavePre",
    callback  = function()
      require('nvim-tree.api').tree.close()
      require('outline').close()
    end,
  }
)

api.nvim_create_autocmd(
  -- FileType only: for BufWinEnter the pattern is matched against the buffer's
  -- FILE NAME, and the outline buffer is unnamed at that point (later
  -- OUTLINE_<tab>), so that half could never fire.
  "FileType",
  {
    group = group,
    pattern = { "Outline" },
    callback = function(args)
      vim.schedule(function()
        -- Find all windows displaying this specific buffer
        local wins = vim.fn.win_findbuf(args.buf)
        for _, win in ipairs(wins) do
          -- Apply only to the sidebar windows, not the current active window
          api.nvim_set_option_value("statuscolumn", "",  { scope = "local", win = win })
          api.nvim_set_option_value("statusline",   " ", { scope = "local", win = win })
        end
      end)
    end,
  }
)

api.nvim_create_autocmd(
  "TextYankPost",
  {
    group     = group,
    desc      = "briefly highlight yanked text",
    callback  = function()
      -- vim.hl.on_yank is deprecated on 0.13+ in favour of vim.hl.hl_op
      local hl = vim.hl.hl_op or vim.hl.on_yank
      hl({ timeout = 150 })
    end,
  }
)

api.nvim_create_autocmd(
  "VimEnter",
  {
    group     = group,
    desc      = "open nvim-tree when nvim starts on a directory (nvim-tree is now lazy-loaded)",
    callback  = function(data)
      if vim.fn.isdirectory(data.file) == 1 then
        vim.cmd.cd(data.file)
        require("nvim-tree.api").tree.open()
      end
    end,
  }
)
