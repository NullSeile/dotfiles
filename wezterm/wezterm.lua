local wezterm = require("wezterm")

local smart_splits = wezterm.plugin.require("https://github.com/mrjones2014/smart-splits.nvim")
-- local bar = wezterm.plugin.require("https://github.com/adriankarlen/bar.wezterm")

local act = wezterm.action
local config = {}

-- config.default_prog = { "pwsh.exe" }
config.default_prog = { "fish" }
-- config.default_prog = { "sh" }
config.color_scheme = "Kanagawa (Desat)"

config.color_schemes = {
    ["Kanagawa (Desat)"] = require("colors.kanagawa-desat"),
}
config.enable_wayland = false
-- config.harfbuzz_features = { "ss02", "ss03", "ss04" }
config.harfbuzz_features = { "ss01", "ss02", "ss03" }
config.font = wezterm.font("Maple Mono NF")

-- config.window_background_opacity = 0.9
config.win32_system_backdrop = "Acrylic"
config.window_decorations = "NONE | RESIZE"

config.window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
}

config.hide_tab_bar_if_only_one_tab = true
-- config.use_fancy_tab_bar = true

-- local function isViProcess(pane)
--     -- get_foreground_process_name On Linux, macOS and Windows,
--     -- the process can be queried to determine this path. Other operating systems
--     -- (notably, FreeBSD and other unix systems) are not currently supported
--     return pane:get_foreground_process_name():find("n?vim") ~= nil
--         or pane:get_title():find("n?vim") ~= nil
--         or pane:get_user_vars().is_vim == "true"
-- end
--
-- local function isSSHProcess(pane)
--     return pane:get_foreground_process_name():find("ssh") ~= nil or pane:get_title():find("ssh") ~= nil
-- end
--
-- local function conditionalActivatePane(window, pane, pane_direction, vim_direction)
--     if isViProcess(pane) or isSSHProcess(pane) then
--         window:perform_action(
--             -- This should match the keybinds you set in Neovim.
--             act.SendKey({ key = vim_direction, mods = "CTRL" }),
--             pane
--         )
--     else
--         window:perform_action(act.ActivatePaneDirection(pane_direction), pane)
--     end
-- end
--
-- wezterm.on("ActivatePaneDirection-right", function(window, pane)
--     conditionalActivatePane(window, pane, "Right", "l")
-- end)
-- wezterm.on("ActivatePaneDirection-left", function(window, pane)
--     conditionalActivatePane(window, pane, "Left", "h")
-- end)
-- wezterm.on("ActivatePaneDirection-up", function(window, pane)
--     conditionalActivatePane(window, pane, "Up", "k")
-- end)
-- wezterm.on("ActivatePaneDirection-down", function(window, pane)
--     conditionalActivatePane(window, pane, "Down", "j")
-- end)
--
-- -- Equivalent to POSIX basename(3)
-- -- Given "/foo/bar" returns "bar"
-- -- Given "c:\\foo\\bar" returns "bar"
-- local function basename(s)
--     return string.gsub(s, "(.*[/\\])(.*)", "%2")
-- end
--
-- local function is_vim(pane)
--     local process_name = basename(pane:get_foreground_process_name())
--     -- log.info("process_name: ", process_name)
--     return process_name == "nvim" or process_name == "vim"
-- end
--
-- local direction_keys = {
--     Left = "h",
--     Down = "j",
--     Up = "k",
--     Right = "l",
--     -- reverse lookup
--     h = "Left",
--     j = "Down",
--     k = "Up",
--     l = "Right",
-- }
--
-- local function split_nav(resize_or_move, key)
--     return {
--         key = key,
--         mods = resize_or_move == "resize" and "META" or "CTRL",
--         action = wezterm.action_callback(function(win, pane)
--             if is_vim(pane) then
--                 -- pass the keys through to vim/nvim
--                 win:perform_action({
--                     SendKey = { key = key, mods = resize_or_move == "resize" and "META" or "CTRL" },
--                 }, pane)
--             else
--                 if resize_or_move == "resize" then
--                     win:perform_action({ AdjustPaneSize = { direction_keys[key], 3 } }, pane)
--                 else
--                     win:perform_action({ ActivatePaneDirection = direction_keys[key] }, pane)
--                 end
--             end
--         end),
--     }
-- end

config.keys = {
    {
        key = "P",
        mods = "CTRL|ALT|SHIFT",
        action = act.ActivateCommandPalette,
    },
    {
        key = "V",
        mods = "CTRL|SHIFT",
        action = act.PasteFrom("Clipboard"),
    },
    {
        key = "C",
        mods = "CTRL|SHIFT",
        action = act.CopyTo("Clipboard"),
    },
    {
        key = "w",
        mods = "CTRL|SHIFT",
        action = act.CloseCurrentPane({ confirm = true }),
    },
    {
        key = "h",
        mods = "CTRL|SHIFT",
        action = act.SplitPane({
            direction = "Left",
            size = { Percent = 50 },
        }),
    },
    {
        key = "l",
        mods = "CTRL|SHIFT",
        action = act.SplitPane({
            direction = "Right",
            size = { Percent = 50 },
        }),
    },
    {
        key = "j",
        mods = "CTRL|SHIFT",
        action = act.SplitPane({
            direction = "Down",
            size = { Percent = 50 },
        }),
    },
    {
        key = "k",
        mods = "CTRL|SHIFT",
        action = act.SplitPane({
            direction = "Up",
            size = { Percent = 50 },
        }),
    },
    -- {
    --     key = "U",
    --     mods = "CTRL|SHIFT",
    --     action = act.AdjustPaneSize({ "Left", 2 }),
    -- },
    -- {
    --     key = "I",
    --     mods = "CTRL|SHIFT",
    --     action = act.AdjustPaneSize({ "Down", 2 }),
    -- },
    -- {
    --     key = "O",
    --     mods = "CTRL|SHIFT",
    --     action = act.AdjustPaneSize({ "Up", 2 }),
    -- },
    -- {
    --     key = "P",
    --     mods = "CTRL|SHIFT",
    --     action = act.AdjustPaneSize({ "Right", 2 }),
    -- },
    { key = "9", mods = "CTRL", action = act.PaneSelect },
    { key = "D", mods = "CTRL|ALT|SHIFT", action = act.ShowDebugOverlay },
    -- { key = "h", mods = "CTRL", action = act.EmitEvent("ActivatePaneDirection-left") },
    -- { key = "j", mods = "CTRL", action = act.EmitEvent("ActivatePaneDirection-down") },
    -- { key = "k", mods = "CTRL", action = act.EmitEvent("ActivatePaneDirection-up") },
    -- { key = "l", mods = "CTRL", action = act.EmitEvent("ActivatePaneDirection-right") },
    {
        key = "O",
        mods = "CTRL|ALT|SHIFT",
        -- toggling opacity
        action = wezterm.action_callback(function(window, _)
            local overrides = window:get_config_overrides() or {}
            if overrides.window_background_opacity == 1.0 then
                overrides.window_background_opacity = 0.9
            else
                overrides.window_background_opacity = 1.0
            end
            window:set_config_overrides(overrides)
        end),
    },
    -- -- move between split panes
    -- split_nav("move", "h"),
    -- split_nav("move", "j"),
    -- split_nav("move", "k"),
    -- split_nav("move", "l"),
    -- -- resize panes
    -- split_nav("resize", "h"),
    -- split_nav("resize", "j"),
    -- split_nav("resize", "k"),
    -- split_nav("resize", "l"),
}

-- bar.apply_to_config(config, {
-- 	modules = {
-- 		username = {
-- 			enabled = false,
-- 		},
-- 		workspace = {
-- 			enabled = false,
-- 		},
-- 		hostname = {
-- 			enabled = false,
-- 		},
-- 		pane = {
-- 			enabled = false,
-- 		},
-- 		spotify = {
-- 			enabled = true,
-- 		},
-- 	},
-- })

smart_splits.apply_to_config(config, {
    -- the default config is here, if you'd like to use the default keys,
    -- you can omit this configuration table parameter and just use
    -- smart_splits.apply_to_config(config)

    -- directional keys to use in order of: left, down, up, right
    -- direction_keys = { "h", "j", "k", "l" },
    -- if you want to use separate direction keys for move vs. resize, you
    -- can also do this:
    direction_keys = {
        move = { "h", "j", "k", "l" },
        resize = { "y", "u", "i", "o" },
    },
    -- modifier keys to combine with direction_keys
    modifiers = {
        move = "CTRL", -- modifier to use for pane movement, e.g. CTRL+h to move left
        resize = "CTRL|SHIFT", -- modifier to use for pane resize, e.g. META+h to resize to the left
    },
    -- log level to use: info, warn, error
    log_level = "trace",
})

return config
