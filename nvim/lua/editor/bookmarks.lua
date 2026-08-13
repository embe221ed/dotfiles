require('bookmarks').setup({
  -- Bookmarks sign configurations
  signs = {
    -- Sign mark icon and color in the gutter
    mark = {
      color = vim.g.colors.alt_fg,
      line_bg = "",
    },
    desc_format = function(bookmark)
      ---@cast bookmark Bookmarks.Node
      return "#" .. bookmark.order .. ": " .. bookmark.name
    end,
  },
  treeview = {
    highlights = {
      active_list = {
        bg = "",
        fg = vim.g.colors.orange,
        bold = true,
      },
    }
  },
  picker = {
    picker_backend = 'snacks',
  },
})

--------------------------------------------------------------------------------
-- snacks picker: draw the bookmark NAME, not just the file it points at
--------------------------------------------------------------------------------
-- bookmarks.nvim builds every picker row as
--     { text = entry_display(bm, all), file = …, pos = …, bookmark = bm }
-- and then hands Snacks `format = "file"`. In Snacks `text` is only the
-- fuzzy-match haystack; what gets DRAWN comes from the formatter, and the
-- built-in "file" one draws icon + path + :line and nothing else. So the name
-- typed at :BookmarksMark is searchable but never visible, and the plugin's
-- `picker.entry_display` option cannot fix it — that only feeds `text`. (It is
-- honoured for real by the telescope backend, picker/telescope/formatter.lua;
-- only the snacks path drops it on the floor.)
--
-- A custom `format` is safe: Snacks re-runs the matcher against the RENDERED
-- line to place match highlights (picker/core/list.lua, List:format), so there
-- are no offsets to keep in sync with `text`.
--
-- All six entry points — BookmarksGoto plus the five link/goto-linked commands —
-- funnel through bookmarks.picker's get_picker(), which resolves to this one
-- cached module, so replacing the single function covers all of them.
local bm_picker = require('bookmarks.picker.snacks.bookmark-picker')
local Repo      = require('bookmarks.domain.repo')
local Node      = require('bookmarks.domain.node')
local Service   = require('bookmarks.domain.service')

local NAME_MIN, NAME_MAX = 15, 30
-- what the rest of the row needs before the name may have any of it: the
-- selected-marker column List:format prepends outside our line (1), " │ " (3),
-- the devicon (2), ":line:col" (~8) and a path still worth reading (~21).
local ROW_OVERHEAD = 35
-- Snacks refuses to truncate a path below formatters.file.min_width, which
-- DEFAULTS TO 40 — wider than what is left once the name column is spent, so
-- the row overflows a `wrap = false` window and the tail is silently cut off.
local PATH_MIN = 12

-- `name` is "" for a bookmark marked by confirming an empty prompt; the line
-- captured at mark time is a better handle than a blank column. Tabs would be
-- measured as one cell and drawn as 'tabstop', so flatten them.
local function label_of(bookmark)
  local label = bookmark.name
  if not label or label == "" then label = vim.trim(bookmark.content or "") end
  if label == "" then return "(unnamed)" end
  return (label:gsub("%s", " "))
end

-- Snacks.picker.util.align truncates with strcharpart — a CHARACTER count —
-- while padding to a display-CELL count, so a CJK or emoji name renders about
-- twice its budget and drags the │ column out of line. Measure in cells on
-- both sides instead.
local function fit(text, width)
  local w = vim.api.nvim_strwidth(text)
  if w <= width then return text .. (" "):rep(width - w) end
  local kept, used = {}, 0
  for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
    local cw = vim.api.nvim_strwidth(ch)
    if used + cw > width - 1 then break end
    kept[#kept + 1] = ch
    used = used + cw
  end
  return table.concat(kept) .. "…" .. (" "):rep(math.max(0, width - used - 1))
end

-- :BookmarksDesc stores a free-form multi-line description; flatten it so it
-- can sit on one row.
local function desc_of(bookmark)
  local desc = vim.trim((bookmark.description or ""):gsub("%s+", " "))
  return desc ~= "" and desc or nil
end

---@param callback fun(bookmark: Bookmarks.Node): nil
---@param opts? {prompt?: string, bookmarks?: Bookmarks.Node[]}
function bm_picker.pick_bookmark(callback, opts)
  opts = opts or {}

  local active_list = Repo.ensure_and_get_active_list()
  local bookmarks   = opts.bookmarks or Node.get_all_bookmarks(active_list)
  local list_name   = opts.bookmarks and "Custom Selection" or active_list.name

  local cfg           = vim.g.bookmarks_config or {}
  local entry_display = cfg.picker and cfg.picker.entry_display

  -- one column width for the whole list, so the paths line up
  local longest = NAME_MIN
  for _, bm in ipairs(bookmarks) do
    longest = math.max(longest, vim.api.nvim_strwidth(label_of(bm)))
  end
  longest = math.min(longest, NAME_MAX)

  -- …but never wider than the window can spare. At <120 columns the layout
  -- preset flips to "vertical" and the list gets the full width; at >=120 it is
  -- half of it (see misc/_snacks.lua), which is ~58 cells — not enough for a
  -- 30-cell name AND a path, and the overflow would be cut off, not wrapped.
  local function name_column(picker)
    local win = picker and picker.list and picker.list.win
    if not (win and win:win_valid()) then return longest end
    return math.max(NAME_MIN, math.min(longest, vim.api.nvim_win_get_width(win.win) - ROW_OVERHEAD))
  end

  local items = {}
  for _, bookmark in ipairs(bookmarks) do
    local desc = desc_of(bookmark)
    items[#items + 1] = {
      -- everything the row shows plus the FULL path, so typing a directory
      -- narrows the list too (upstream only put the basename in here)
      text     = entry_display and entry_display(bookmark, bookmarks)
        or table.concat({ label_of(bookmark), bookmark.location.path, desc or "" }, " "),
      file     = bookmark.location.path,
      pos      = { bookmark.location.line, bookmark.location.col },
      bookmark = bookmark,
      bm_desc  = desc,
    }
  end

  Snacks.picker({
    title      = opts.prompt or ("Bookmarks in [" .. list_name .. "]"),
    items      = items,
    preview    = "file",
    -- per-picker override, deep-merged over the defaults; leaves every other
    -- Snacks picker on the stock 40
    formatters = { file = { min_width = PATH_MIN } },
    format     = function(item, picker)
      local ret = {
        { fit(label_of(item.bookmark), name_column(picker)), "SnacksPickerLabel" },
        { " │ ", "SnacksPickerDelim" },
      }
      -- reuse the built-in one for the right-hand side: devicon, cwd-relative
      -- truncation and :line:col all come for free
      vim.list_extend(ret, Snacks.picker.format.filename(item, picker))
      if item.bm_desc then
        -- a `resolve` segment is handed whatever width is left after everything
        -- else on the row (util/highlight.lua M.resolve), so the description
        -- takes the slack and never pushes the path off the edge
        ret[#ret + 1] = {
          "",
          resolve = function(max_width)
            -- less one: List:format prepends a selected-marker cell that is not
            -- part of this line, but passes the FULL window width as max_width
            max_width = max_width - 1
            if max_width < 4 then return {} end
            return { { fit(item.bm_desc, max_width):gsub("%s+$", ""), "SnacksPickerComment" } }
          end,
        }
      end
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        callback(item.bookmark)
      end
    end,
    actions = {
      delete_bookmark = function(picker, item)
        if not item or not item.bookmark then
          return
        end
        local id = item.bookmark.id
        Service.delete_node(id)
        picker:close()
        -- Reopen with updated bookmarks. `opts.bookmarks` is a captured array
        -- (the Goto-linked-in/out commands pass one) — reopening with it
        -- verbatim would re-list the row we just deleted, and <CR> on that
        -- ghost throws "Bookmark not found" out of Service.goto_bookmark.
        local next_opts = opts
        if opts.bookmarks then
          next_opts = vim.tbl_extend("force", {}, opts, {
            bookmarks = vim.tbl_filter(function(b) return b.id ~= id end, opts.bookmarks),
          })
        end
        vim.schedule(function()
          bm_picker.pick_bookmark(callback, next_opts)
        end)
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-d>"] = { "delete_bookmark", mode = { "i", "n" }, desc = "Delete bookmark" },
        },
      },
    },
  })
end
