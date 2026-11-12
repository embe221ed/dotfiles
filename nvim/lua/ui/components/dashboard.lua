-- A quiet, keyboard-first home screen for snacks.dashboard.
-- Inspired by the compact layouts in folke/snacks.nvim discussions/111.

local function highlights()
  local colors = vim.g.colors
  local groups = {
    DashboardBrand = { fg = colors.fg, bold = true },
    DashboardAccent = { fg = colors.accent, bold = true },
    DashboardLogo = { fg = colors.blue },
    DashboardMuted = { link = "Comment" },
    DashboardRule = { fg = colors.alt_fg },
    DashboardKey = { fg = colors.accent, bg = colors.light_bg, bold = true },
    DashboardPrimary = { fg = colors.bg, bg = colors.accent, bold = true },
  }
  for name, value in pairs(groups) do
    vim.api.nvim_set_hl(0, name, value)
  end
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("user_dashboard_colors", { clear = true }),
  callback = highlights,
})

-- Trim by display cells, preserving Unicode filenames and useful path endings.
local function fit(text, width, tail)
  if width <= 0 then return "" end
  if vim.fn.strdisplaywidth(text) <= width then return text end
  local count = vim.fn.strchars(text)
  while count > 0 do
    count = count - 1
    local part = vim.fn.strcharpart(text, tail and vim.fn.strchars(text) - count or 0, count)
    if vim.fn.strdisplaywidth(part) < width then
      return tail and "…" .. part or part .. "…"
    end
  end
  return "…"
end

local function useful_path(path)
  for _, cache in ipairs({ "/.move/", "/.git/", "/node_modules/", "/.cargo/registry/" }) do
    if (path .. "/"):find(cache, 1, true) then return false end
  end
  return true
end

local keys = {
  { key = "f", desc = "files",    action = function() Snacks.picker.files() end },
  { key = "w", desc = "search",   action = function() Snacks.picker.grep() end },
  { key = "r", desc = "resume",   action = function() require('persistence').load() end },
  { key = "e", desc = "browse",   action = function() Snacks.explorer.open() end },
  { key = "h", desc = "history",  action = function() Snacks.picker.recent() end },
  { key = "s", desc = "sessions", action = function() require('persistence').select() end },
  { key = "u", desc = "update",   action = ":Lazy sync" },
  { key = "q", desc = "quit",     action = ":qa" },
  { key = "d", desc = "LSP debug level", action = ':lua vim.lsp.log.set_level("debug")' },
}

-- Hidden bindings let the command strips stay compact; numbered rows use Enter.
local bindings = vim.deepcopy(keys)
for _, key in ipairs(bindings) do key.hidden = true end

local function command_rows(first, last, width, primary)
  local rows, text, used = {}, {}, 0
  for i = first, last do
    local item = keys[i]
    local length = #item.desc + 4
    if used > 0 and used + 3 + length > width then
      rows[#rows + 1] = { text = text }
      text, used = {}, 0
    end
    if used > 0 then
      text[#text + 1] = { "   " }
      used = used + 3
    end
    text[#text + 1] = { " " .. item.key .. " ", hl = primary and i == first and "DashboardPrimary" or "DashboardKey" }
    text[#text + 1] = { " " .. item.desc, hl = primary and "DashboardBrand" or "DashboardMuted" }
    used = used + length
  end
  rows[#rows + 1] = { text = text }
  return rows
end

local function heading(label, count, width)
  return {
    text = {
      { label, hl = "DashboardMuted", width = width - 3 },
      { ("%02d"):format(count), hl = "DashboardMuted", width = 3, align = "right" },
    },
  }
end

return {
  enabled = true,
  width = 72,
  preset = { keys = bindings },
  formats = {
    key = function(item)
      -- Separate chunks keep Snacks' alignment spacer outside the badge background.
      return {
        { " ", hl = "DashboardKey" },
        { item.key .. " ", hl = "DashboardKey" },
      }
    end,
    file = function(item, ctx)
      local name = vim.fn.fnamemodify(item.file, ":t")
      if ctx.width < 48 then
        return { fit(name, ctx.width), hl = "DashboardBrand" }
      end
      local name_width = math.floor(ctx.width * 0.52)
      local parent = vim.fn.fnamemodify(item.file, ":h:~")
      return {
        { fit(name, name_width - 2), hl = "DashboardBrand", width = name_width },
        { fit(parent, ctx.width - name_width, true), hl = "DashboardMuted",
          width = ctx.width - name_width, align = "right" },
      }
    end,
  },
  sections = function(self)
    highlights()
    local width = math.min(72, math.max(16, self:size().width - 4))
    self.opts.width = width
    local height = vim.api.nvim_win_get_height(self.win)
    local compact = width < 56 or height < 22
    local primary = command_rows(1, 4, width, true)
    local secondary = command_rows(5, 8, width, false)
    local header_height = compact and 2 or 5
    -- Headings, command strips, rules and breathing room are fixed-height.
    local available = height - header_height - #primary - #secondary - 10
    local limit = math.min(3, math.max(0, math.floor(available / 2)))
    local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
    local project = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
    local version = vim.version()
    local stats = require('lazy.stats').stats()
    local meta = ("v%d.%d.%d  ·  %d plugins"):format(version.major, version.minor, version.patch, stats.loaded)
    local result = { { section = "keys" } }

    if compact then
      result[#result + 1] = { text = {
        { "◈  ", hl = "DashboardAccent" }, { "neovim", hl = "DashboardBrand" },
        { "  /  " .. fit(project, width - 15), hl = "DashboardMuted" },
      } }
      result[#result + 1] = { text = { fit(cwd, width), hl = "DashboardMuted" }, padding = 1 }
    else
      local logo = { "▄▄      ▄▄", "███▄    ██", "██ ▀█▄  ██", "██   ▀█▄██", "▀▀     ▀▀▀" }
      local details = {
        { "n e o v i m", hl = "DashboardBrand" },
        { "" },
        { fit(project, width - 16), hl = "DashboardAccent" },
        { fit(cwd, width - 16), hl = "DashboardMuted" },
        { "" },
      }
      for i, line in ipairs(logo) do
        local text = {
          { line:sub(1, #line - 6), hl = "DashboardAccent" },
          { line:sub(-6), hl = "DashboardLogo" },
          { "    " }, details[i],
        }
        if i == 1 then
          text[4].width = width - 14 - 14
          text[#text + 1] = { os.date("%a, %d %b"):upper(), hl = "DashboardMuted", width = 14, align = "right" }
        end
        result[#result + 1] = { text = text, padding = i == #logo and 1 or nil }
      end
    end

    vim.list_extend(result, primary)
    result[#result + 1] = { text = { ("─"):rep(width), hl = "DashboardRule" }, padding = 1 }

    local function recent(label, items)
      result[#result + 1] = heading(label, #items, width)
      if #items == 0 then
        result[#result + 1] = { text = { "Nothing here yet", hl = "DashboardMuted" } }
      else
        for _, item in ipairs(items) do
          item.icon = nil
          result[#result + 1] = item
        end
      end
      result[#result].padding = 1
    end
    if limit > 0 then
      recent("RECENT PROJECTS", Snacks.dashboard.sections.projects({ limit = limit, filter = useful_path }))
      recent("RECENT FILES", Snacks.dashboard.sections.recent_files({ limit = limit, filter = useful_path })())
    end

    result[#result + 1] = { text = { ("─"):rep(width), hl = "DashboardRule" } }
    vim.list_extend(result, secondary)
    result[#result + 1] = { text = { fit(meta, width), hl = "DashboardMuted" }, align = "right" }
    return result
  end,
}
