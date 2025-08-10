local expscroll = {}

local ctrl_y = vim.api.nvim_replace_termcodes("<C-y>", false, false, true)
local ctrl_e = vim.api.nvim_replace_termcodes("<C-e>", false, false, true)

local state = 
{
  lines_to_scroll = 0,
  lines_scrolled = 0,
  timer = vim.loop.new_timer(),
  scrolling = false,
  scroll_cursor = false,
  scroll_window = false,
  t = 0,
}

local debugging = false

-- animations
-- frame dt (60 FPS)
local target_fps = 60.0
local target_frame_dt_ms = 1000.0/target_fps
local target_frame_dt_secs = 1.0/target_fps

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
  if frame_dt_secs > 0 then
    local fps = 1.0/frame_dt_secs
    print("fps", fps, "frame_dt_secs", frame_dt_secs)
  end

  local scrolling = state.scrolling
  if scrolling then
    local lines_to_scroll = state.lines_to_scroll - state.lines_scrolled
    dprint("lines_to_scroll total", state.lines_to_scroll)
    dprint("lines_scrolled ", state.lines_to_scroll)
    dprint("lines_to_scroll ", lines_to_scroll)

    if lines_to_scroll ~= 0 then

      local lines_to_scroll_this_frame = 0

      local vast_rate = 1 - (2 ^ (-60.0 * frame_dt_secs))
      local fast_rate = 1 - (2 ^ (-50.0 * frame_dt_secs))
      local fish_rate = 1 - (2 ^ (-40.0 * frame_dt_secs))
      local slow_rate = 1 - (2 ^ (-30.0 * frame_dt_secs))
      local slug_rate = 1 - (2 ^ (-15.0 * frame_dt_secs))
      local slaf_rate = 1 - (2 ^ (-8.0  * frame_dt_secs))

      lines_to_scroll_this_frame = fast_rate * lines_to_scroll + state.t
      state.t = lines_to_scroll_this_frame - math.floor(lines_to_scroll_this_frame)
      lines_to_scroll_this_frame = math.floor(lines_to_scroll_this_frame)

      -- if lines_to_scroll > 0 then
      --   lines_to_scroll_this_frame = math.ceil(fast_rate * lines_to_scroll)
      -- else
      --   lines_to_scroll_this_frame = math.floor(fast_rate * lines_to_scroll)
      -- end

      local count = math.abs(lines_to_scroll_this_frame)
      dprint("lines_to_scroll_this_frame", lines_to_scroll_this_frame)

      local cursor_scroll_cmd = lines_to_scroll > 0 and count .. "gj" or count .. "gk"
      local cursor_scroll_args = state.scroll_cursor and cursor_scroll_cmd or ""
      local window_scroll_cmd = lines_to_scroll > 0 and count .. ctrl_e or count .. ctrl_y
      local window_scroll_args = state.scroll_window and window_scroll_cmd or ""
      local scroll_args = window_scroll_args .. cursor_scroll_args

      dprint("scroll_args ", scroll_args)
      if lines_to_scroll_this_frame ~= 0 then
        state.lines_scrolled = state.lines_scrolled + lines_to_scroll_this_frame
        vim.cmd.normal({ bang = true, args = { scroll_args } })
      end

      -- local scroll_func = function()
      --   vim.cmd.normal({ bang = true, args = { scroll_args } })
      -- end
    else
      scrolling = false
    end
  end

  state.scrolling = scrolling

  if not scrolling then
    dprint("done")
    state.timer:stop()
  else
    dprint("scrolling")
  end
end

function expscroll.ctrl_u()
  init()

  local target_line = buf_pos[1] - half_win_line
  target_line = math.max(1, target_line)

  state.lines_to_scroll = target_line - buf_pos[1]
  state.lines_scrolled = 0
  state.scroll_cursor = true
  state.scroll_window = true
  last_time = vim.loop.hrtime()

  if not state.scrolling then
    state.scrolling = true
    -- NOTE: nvim_cmd must not be called in a fast event context
    state.timer:start(0, target_frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
  end
end

function expscroll.ctrl_d()
  init()

  local target_line = buf_pos[1] + half_win_line
  target_line = math.min(target_line, buf_line_count)

  state.lines_to_scroll = target_line - buf_pos[1]
  state.lines_scrolled = 0
  state.scroll_cursor = true
  state.scroll_window = true
  last_time = vim.loop.hrtime()

  if not state.scrolling then
    state.scrolling = true
    state.timer:start(0, target_frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
  end
end

function expscroll.j()
  init()

  local count = vim.v.count
  if count ~= 0 then
    local lines_to_scroll = count 
    local target_line = buf_pos[1] + lines_to_scroll
    target_line = math.min(target_line, buf_line_count)

    state.lines_to_scroll = target_line - buf_pos[1]
    state.lines_scrolled = 0
    state.scroll_cursor = true
    state.scroll_window = false
    last_time = vim.loop.hrtime()

    if not state.scrolling then
      state.scrolling = true
      state.timer:start(0, target_frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
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

    state.lines_to_scroll = target_line - buf_pos[1]
    state.lines_scrolled = 0
    state.scroll_cursor = true
    state.scroll_window = false
    last_time = vim.loop.hrtime()

    if not state.scrolling then
      state.scrolling = true
      state.timer:start(0, target_frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
    end
  else
    vim.cmd.normal({ bang = true, args = { "k" } })
  end
end

function expscroll.gg()
  init()

  local target_line = 1
  state.lines_to_scroll = target_line - buf_pos[1]
  state.lines_scrolled = 0
  state.scroll_cursor = true
  state.scroll_window = true
  last_time = vim.loop.hrtime()

  if not state.scrolling then
    state.scrolling = true
    state.timer:start(0, target_frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
  end
end

function expscroll.G()
  init()

  local target_line = buf_line_count
  state.lines_to_scroll = target_line - buf_pos[1]
  state.lines_scrolled = 0
  state.scroll_cursor = true
  state.scroll_window = true
  last_time = vim.loop.hrtime()

  if not state.scrolling then
    state.scrolling = true
    state.timer:start(0, target_frame_dt_ms, vim.schedule_wrap(expscroll.scroll))
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
  -- ["<C-b>"] = function() neoscroll.ctrl_b({duration = 450}) end;
  -- ["<C-f>"] = function() neoscroll.ctrl_f({duration = 450}) end;
  -- ["<C-y>"] = function() neoscroll.scroll(-0.1, { move_cursor=false; duration = 100}) end;
  -- ["<C-e>"] = function() neoscroll.scroll(0.1, {move_cursor=false; duration = 100}) end;
  -- ["zt"]    = function() neoscroll.zt({half_win_duration = 250}) end;
  -- ["zb"]    = function() neoscroll.zb({half_win_duration = 250}) end;
}

function expscroll.setup()
  local modes = { "n", "v", "x" }

  vim.keymap.set("n", "<C-u>", function_mappings["<C-u>"])
  vim.keymap.set("n", "<C-d>", function_mappings["<C-d>"])
  vim.keymap.set("n", "j", function_mappings["j"])
  vim.keymap.set("n", "k", function_mappings["k"])
  vim.keymap.set("n", "gg", function_mappings["gg"])
  vim.keymap.set("n", "G", function_mappings["G"])
  -- vim.keymap.set("n", "zz", function_mappings["zz"])

  -- some performance settings
  vim.opt.lazyredraw = true
  vim.ttyfast = true
end

return expscroll
