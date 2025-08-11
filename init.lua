local expscroll = {}

local ctrl_y = vim.api.nvim_replace_termcodes("<C-y>", false, false, true)
local ctrl_e = vim.api.nvim_replace_termcodes("<C-e>", false, false, true)

-----------------------------------------------------------------------------------------
-- Cursor settings

-- Highlight group to hide the cursor
-- local hl_callback = function()
--   vim.api.nvim_set_hl(
--     0,
--     "NeoscrollHiddenCursor",
--     { reverse = true, blend = 100 }
--   )
-- end
-- hl_callback()
-- local cursor_group = vim.api.nvim_create_augroup("NeoscrollHiddenCursor", {})
-- vim.api.nvim_create_autocmd(
--   { "ColorScheme" },
--   { group = cursor_group, callback = hl_callback }
-- )
-- -----------------------------------------------------------------------------------------

local state = 
{
  window_lines_to_scroll = 0,
  window_lines_scrolled = 0,
  cursor_lines_to_scroll = 0,
  cursor_lines_scrolled = 0,
  timer = vim.loop.new_timer(),
  scrolling = false,
  scrolling_last_frame = false,
  -- guicursor = ""
}

local debugging = false

-- animations
-- frame dt (60 FPS)
local target_fps = 60.0
-- NOTE: ms is taken as integer
local target_frame_dt_ms = 1000.0/target_fps - 1

-- current win handler
local win = vim.api.nvim_get_current_win()
-- current buf handler
local buf = vim.api.nvim_get_current_buf()
-- buf total line count
local buf_line_count = vim.api.nvim_buf_line_count(buf)
-- win display line count
local win_line_count = vim.api.nvim_win_get_height(win)
-- win disply half line count
local half_win_line = math.ceil(win_line_count / 2) - 1
-- cur pos relative to buf
local buf_pos = vim.api.nvim_win_get_cursor(win)
-- cur line relative to win
-- local win_line = vim.api.nvim_call_function('winline', {})
local win_line = vim.api.nvim_win_call(win, vim.fn.winline)
-- bottom line of buf displayed
local bottom_line = win_line_count - win_line + buf_pos[1]
-- top line of buf displayed
local top_line = buf_pos[1] - win_line + 1
local last_time = vim.loop.hrtime()

local function dprint(...)
  if debugging then
    print(...)
  end
end

local function pre_book()
  vim.opt.eventignore:append({
    'WinScrolled',
    'CursorMoved',
  })
end

local function post_hook()
  vim.opt.eventignore:remove({
    'WinScrolled',
    'CursorMoved',
  })
end

local function clamp(mn, v, mx)
  return math.min(math.max(mn, v), mx)
end

local function init()
	win = vim.api.nvim_get_current_win()
	buf = vim.api.nvim_get_current_buf()
	buf_line_count = vim.api.nvim_buf_line_count(buf)
	win_line_count = vim.api.nvim_win_get_height(win)
	half_win_line = math.ceil(win_line_count / 2)
	buf_pos = vim.api.nvim_win_get_cursor(win)
	win_line = vim.api.nvim_call_function('winline', {})
	bottom_line = win_line_count - win_line + buf_pos[1]
	top_line = buf_pos[1] - win_line + 1
end

function expscroll.scroll()
  local now = vim.loop.hrtime()
  local frame_dt_secs = (now - last_time) / 1e9
  last_time = now
  local fps = 0
  if frame_dt_secs > 0 then
    fps = 1.0/frame_dt_secs
    print("fps", fps, "frame_dt_secs", frame_dt_secs)
  end

  local scrolling = state.scrolling
  if scrolling then
    print("state", fps, state.window_lines_to_scroll, state.window_lines_scrolled, state.cursor_lines_to_scroll, state.cursor_lines_scrolled)
    if scrolling ~= state.scrolling_last_frame then
      dprint("pre_book")
      pre_book()
    end

    -- hide cursor
    -- vim.opt.guicursor = ""
    -- if vim.o.termguicolors and vim.o.guicursor ~= "" and vim.o.guicursor ~= "a:NeoscrollHiddenCursor" then
    --   state.guicursor = vim.o.guicursor
    --   vim.o.guicursor = "a:NeoscrollHiddenCursor"
    -- end

    local vast_rate = 1 - (2 ^ (-60.0 * frame_dt_secs))
    local fast_rate = 1 - (2 ^ (-50.0 * frame_dt_secs))
    local fish_rate = 1 - (2 ^ (-40.0 * frame_dt_secs))
    local slow_rate = 1 - (2 ^ (-30.0 * frame_dt_secs))
    local slug_rate = 1 - (2 ^ (-15.0 * frame_dt_secs))
    local slaf_rate = 1 - (2 ^ (-8.0  * frame_dt_secs))

    -- local rate = slaf_rate
    local rate = slaf_rate

    local scroll_this_frame = false
    local scroll_args = ""

    -- window lines scroll
    local window_scroll_args = ""
    do
      local lines_to_scroll = state.window_lines_to_scroll - state.window_lines_scrolled
      local scroll_direction = lines_to_scroll < 0 and -1 or 1
      lines_to_scroll = math.abs(lines_to_scroll)

      if lines_to_scroll > 0 then
        local lines_to_scroll_this_frame = rate * lines_to_scroll
        lines_to_scroll_this_frame = math.ceil(lines_to_scroll_this_frame)
        lines_to_scroll_this_frame = clamp(0, lines_to_scroll_this_frame, lines_to_scroll)
        print("window_lines_to_scroll_this_frame", lines_to_scroll_this_frame, "lines_to_scroll", lines_to_scroll)

        if lines_to_scroll_this_frame ~= 0 then
          window_scroll_args = scroll_direction == 1 and lines_to_scroll_this_frame .. ctrl_e or lines_to_scroll_this_frame .. ctrl_y
          scroll_this_frame = true
          state.window_lines_scrolled = state.window_lines_scrolled + lines_to_scroll_this_frame*scroll_direction

          scrolling = state.window_lines_to_scroll ~= state.window_lines_scrolled
        end
      end
    end

    -- cursor lines scroll
    local cursor_scroll_args = ""
    do
      local lines_to_scroll = state.cursor_lines_to_scroll - state.cursor_lines_scrolled
      local scroll_direction = lines_to_scroll < 0 and -1 or 1
      lines_to_scroll = math.abs(lines_to_scroll)

      if lines_to_scroll > 0 then
        local lines_to_scroll_this_frame = rate * lines_to_scroll
        lines_to_scroll_this_frame = math.ceil(lines_to_scroll_this_frame)
        lines_to_scroll_this_frame = clamp(0, lines_to_scroll_this_frame, lines_to_scroll)
        print("cursor_lines_to_scroll_this_frame", lines_to_scroll_this_frame)

        if lines_to_scroll_this_frame ~= 0 then
          cursor_scroll_args = scroll_direction == 1 and lines_to_scroll_this_frame .. "gj" or lines_to_scroll_this_frame .. "gk"
          scroll_this_frame = true
          state.cursor_lines_scrolled = state.cursor_lines_scrolled + lines_to_scroll_this_frame*scroll_direction

          if state.cursor_lines_to_scroll == state.cursor_lines_scrolled then
            scrolling = scrolling or false
          else
            scrolling = true
          end
        end
      end
    end

    scroll_args = cursor_scroll_args .. window_scroll_args
    if scroll_this_frame then
      print("scroll_args:", scroll_args)
      vim.cmd.normal({ bang = true, args = { scroll_args } })
    end
  end

  state.scrolling = scrolling

  if not scrolling then
    dprint("done", state.window_lines_to_scroll, state.window_lines_scrolled)
    state.timer:stop()

    -- -- show cursor
    -- if vim.o.guicursor == "a:NeoscrollHiddenCursor" then
    --   print("show", state.guicursor)
    --   vim.o.guicursor = state.guicursor
    -- end
  else
    dprint("scrolling")
  end
end

function expscroll.ctrl_u()
  init()

  local target_line = buf_pos[1] - half_win_line
  target_line = math.max(1, target_line)

  if target_line ~= buf_pos[1] then
    state.window_lines_to_scroll = target_line - buf_pos[1]
    state.window_lines_scrolled = 0
    state.cursor_lines_to_scroll = state.window_lines_to_scroll
    state.cursor_lines_scrolled = 0
    last_time = vim.loop.hrtime()
    if not state.scrolling then
      state.scrolling = true
      state.timer:again()
    end
  end
end

function expscroll.ctrl_d()
  init()

  local target_line = buf_pos[1] + half_win_line
  -- TEST
  -- local target_line = buf_pos[1] + 3
  target_line = math.min(target_line, buf_line_count)

  if target_line ~= buf_pos[1] then
    state.window_lines_to_scroll = target_line - buf_pos[1]
    state.window_lines_scrolled = 0
    state.cursor_lines_to_scroll = state.window_lines_to_scroll
    state.cursor_lines_scrolled = 0
    last_time = vim.loop.hrtime()

    if not state.scrolling then
      state.scrolling = true
      state.timer:again()
    end
  end
end

function expscroll.j()
  init()

  local count = vim.v.count
  if count ~= 0 then
    local lines_to_scroll = count 
    local target_line = buf_pos[1] + lines_to_scroll
    target_line = math.min(target_line, buf_line_count)

    state.window_lines_to_scroll = 0
    state.window_lines_scrolled = 0
    state.cursor_lines_to_scroll = target_line - buf_pos[1]
    state.cursor_lines_scrolled = 0
    last_time = vim.loop.hrtime()

    if not state.scrolling then
      state.scrolling = true
      state.timer:again()
    end
  else
    vim.cmd.normal({ bang = true, args = { "j" } })
  end
end

function expscroll.k()
  init()

  local count = vim.v.count
  if count ~= 0 then
    local lines_to_scroll = -1 * count 
    local target_line = buf_pos[1] + lines_to_scroll
    target_line = math.min(target_line, buf_line_count)

    state.window_lines_to_scroll = 0
    state.window_lines_scrolled = 0
    state.cursor_lines_to_scroll = target_line - buf_pos[1]
    state.cursor_lines_scrolled = 0
    last_time = vim.loop.hrtime()

    if not state.scrolling then
      state.scrolling = true
      state.timer:again()
    end
  else
    vim.cmd.normal({ bang = true, args = { "k" } })
  end
end

function expscroll.gg()
  init()
  local target_line = 1

  state.window_lines_to_scroll = target_line - buf_pos[1]
  state.window_lines_scrolled = 0
  state.cursor_lines_to_scroll = state.window_lines_to_scroll
  state.cursor_lines_scrolled = 0
  last_time = vim.loop.hrtime()

  if not state.scrolling then
    state.scrolling = true
    state.timer:again()
  end
end

function expscroll.G()
  init()
  local target_line = buf_line_count

  state.window_lines_to_scroll = target_line - buf_pos[1]
  state.window_lines_scrolled = 0
  state.cursor_lines_to_scroll = state.window_lines_to_scroll
  state.cursor_lines_scrolled = 0
  last_time = vim.loop.hrtime()

  if not state.scrolling then
    state.scrolling = true
    state.timer:again()
    -- state.timer:start(0, target_frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
  end
end

-- function expscroll.zz()
--   init()
--   local middle_line = math.floor((bottom_line+top_line) / 2)
-- 
--   print("middle_line", middle_line, "line_to_scroll", buf_pos[1]-middle_line)
-- 
--   state.curr_line = buf_pos[1]
--   state.target_line = buf_pos[1]-middle_line
--   state.scroll_cursor = false
--   state.scroll_window = true
-- 
--   if not state.scrolling then
--     state.scrolling = true
--     state.timer:start(0, frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
--   end
-- end

local function_mappings = {
  ["<C-u>"] = function() expscroll.ctrl_u() end;
  ["<C-d>"] = function() expscroll.ctrl_d() end;
  ["j"]     = function() expscroll.j() end;
  ["k"]     = function() expscroll.k() end;
  ["G"]     = function() expscroll.G() end;
  ["gg"]    = function() expscroll.gg() end;
  -- ["zz"]    = function() expscroll.zz() end;
}

function expscroll.setup()
  local modes = { "n", "v", "x" }

  vim.keymap.set("n", "<C-u>", function_mappings["<C-u>"])
  vim.keymap.set("n", "<C-d>", function_mappings["<C-d>"])
  -- vim.keymap.set("n", "j", function_mappings["j"])
  -- vim.keymap.set("n", "k", function_mappings["k"])
  -- vim.keymap.set("n", "gg", function_mappings["gg"])
  -- vim.keymap.set("n", "G", function_mappings["G"])
  -- vim.keymap.set("n", "zz", function_mappings["zz"])

  -- some performance settings
  vim.opt.lazyredraw = true
  vim.ttyfast = true
  state.timer:start(0, target_frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
  state.timer:stop()
end

return expscroll
