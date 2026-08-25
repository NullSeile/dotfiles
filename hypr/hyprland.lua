------------------
---- MONITORS ----
------------------

-- hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "auto", scale = "auto" })
-- hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "auto", scale = "auto" })
-- hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "auto", scale = "auto" })
-- hl.monitor({
--     output = "HDMI-A-1",
--     mode = "highrr",
--     position = "auto-left",
-- })
-- hl.monitor({
--     output = "HDMI-A-1",
--     mode = "1920x1080@60",
--     position = "auto",
--     mirror = "eDP-1",
-- })

-- For Noctalia Color templates

hl.config({
    debug = {
        suppress_errors = false,
        disable_logs = false,
    },
})

---------------------
---- MY PROGRAMS ----
---------------------

local USE_HY3 = true

local hy3 = nil
if USE_HY3 then
    hy3 = hl.plugin.hy3
end

local ipc = "noctalia msg "
-- local ipc = "qs -c noctalia-shell ipc call"
local terminal = "GTK_IM_MODULE=simple ghostty"
local browser = "helium-browser"
local fileManager = "nautilus"
local menu = ipc .. "panel-toggle launcher"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("otd-daemon")
    hl.exec_cmd("syncthing --no-browser")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("hyprpm reload -n")
    -- hl.exec_cmd("systemctl --user start himawari.service")
    -- hl.exec_cmd("swaybg -i /home/lia/dotfiles/himawari-wallpaper/lastest.png -m fill")
    hl.exec_cmd("noctalia")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_THEME", "Bibata-Original-Classic")
hl.env("XCURSOR_SIZE", "24")

hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("LIBVA_DRIVER_NAME", "iHD")

-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
-- hl.env("GBM_BACKEND", "nvidia-drm")
-- hl.env("NVD_BACKEND", "direct")

hl.env("XDG_SESSION_TYPE", "wayland")

hl.env("GTK_IM_MODULE", "ibus")
hl.env("QT_IM_MODULE", "ibus")
hl.env("XMODIFIERS", "@im=ibus")

-----------------------
---- LOOK AND FEEL ----
-----------------------
local function set_noctalia_profile(profile)
    local home = os.getenv("HOME")
    local path = home .. "/.config/noctalia/active-profile.toml"

    local f = io.open(path, "w")
    if not f then
        hl.notification.create({ text = "Failed to write " .. path, timeout = 3000, icon = "error" })
        return
    end

    f:write('[include]\nfiles = ["profiles/' .. profile .. '"]\n')
    f:close()

    -- reload noctalia so it picks up the change
    -- hl.dispatch(hl.dsp.exec_cmd("noctalia msg config-reload"))
end

local focus = false

local function update_borders()
    local ws = hl.get_active_workspace()
    if ws == nil then
        return
    end
    local windows = hl.get_workspace_windows(ws)
    local n_visible = 0
    for _, win in ipairs(windows) do
        if win.visible then
            n_visible = n_visible + 1
        end
    end

    hl.window_rule({
        match = {
            workspace = ws.name,
            fullscreen_state_client = 0,
            float = false,
        },
        border_size = n_visible == 1 and 0 or 2,
        rounding = focus and 0 or (n_visible == 1 and 7 or 5),
    })
    -- hl.dispatch(hy3.debug_nodes())
end

local function apply_config()
    local noctalia = require("noctalia")
    local colors = noctalia.colors
    noctalia.apply_theme()

    set_noctalia_profile(focus and "focus.toml" or "base")

    if USE_HY3 then
        hl.config({
            plugin = {
                hy3 = {
                    tabs = {
                        render_text = false,
                        padding = focus and 0 or 5,
                        radius = focus and 0 or 5,
                        border_width = 0,
                        height = 8,

                        colors = {
                            active = colors.secondary,
                            active_border = colors.secondary,

                            active_alt_monitor = colors.primary,
                            active_alt_monitor_border = colors.primary,

                            focused = colors.primary,
                            focused_border = colors.primary,

                            inactive = colors.surface,
                            inactive_border = colors.surface_variant,

                            urgent = colors.error,
                            urgent_border = colors.error,
                        },
                    },
                    autotile = {
                        enable = true,
                        ephemeral_groups = true,
                    },
                },
            },
        })
    end

    hl.config({
        cursor = {
            no_hardware_cursors = true,
            hide_on_key_press = false,
            inactive_timeout = 2,
        },

        general = {
            gaps_in = focus and 0 or 5,
            gaps_out = focus and 0 or 10,
            border_size = 2,

            snap = { enabled = true },
            resize_on_border = true,
            allow_tearing = false,
            layout = USE_HY3 and "hy3" or "dwindle",
        },

        decoration = {
            rounding = focus and 0 or 5,
            rounding_power = 2,
            shadow = { enabled = false },
            blur = { enabled = false },
        },

        animations = {
            enabled = false, -- "no, please :)"
        },

        misc = {
            force_default_wallpaper = 2,
            disable_hyprland_logo = true,
            enable_anr_dialog = false,
            focus_on_activate = true,
        },

        input = {
            kb_layout = "es",
            resolve_binds_by_sym = true,
            kb_variant = "",
            kb_model = "",
            kb_options = "",
            kb_rules = "",
            follow_mouse = true,
            float_switch_override_focus = 0,
            sensitivity = 0,
            numlock_by_default = true,
            touchpad = {
                scroll_factor = 1,
                natural_scroll = true,
                disable_while_typing = false,
            },
        },
    })

    -- hl.window_rule({
    --     match = {
    --         workspace = "w[t1]",
    --         fullscreen_state_client = 0,
    --         float = false,
    --     },
    --     border_size = 0,
    --     rounding = focus and 0 or 7,
    -- })
    --
    hl.window_rule({
        match = {
            fullscreen_state_client = 1,
        },
        border_color = colors.secondary,
    })

    hl.window_rule({
        match = {
            xwayland = 1,
        },
        border_color = colors.error,
    })

    update_borders()
end
apply_config()

---------------------
---- KEYBINDINGS ----
---------------------

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

local mainMod = "ALT"
local wmMod = mainMod .. " + CTRL"

-- Example binds
-- hl.bind(mainMod .. " + CONTROL + S", hl.dsp.exec_cmd(ipc .. " settings toggle"))
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SHIFT + RETURN", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + CONTROL + RETURN", hl.dsp.exec_cmd(ipc .. "bar-toggle"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + 2", function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    update_borders()
end)
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + CONTROL + SPACE", hl.dsp.exec_cmd(menu))

-- Fullscreen dispatcher does not have a native dsp yet, fallback to exec_cmd with hyprctl
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + Z", hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" }))

-- hy3 specific dispatchers or dwindle fallback
if USE_HY3 then
    hl.bind(mainMod .. " + W", function()
        hl.dispatch(hy3.change_group("toggletab"))
        update_borders()
    end)
else
    hl.bind(mainMod .. " + W", hl.dsp.group.toggle())
    hl.bind(mainMod .. " + S", hl.dsp.layout("togglesplit"))
end

hl.bind(mainMod .. " + CONTROL + F", function()
    focus = not focus
    apply_config()
end)

hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(ipc .. "screenshot-region"))
hl.bind(mainMod .. " + CONTROL + SHIFT + S", hl.dsp.exec_cmd(ipc .. "panel-toggle alexander/screen-toolkit:panel"))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd(ipc .. "plugin oldirtty/color_picker:service all pick"))
hl.bind(mainMod .. " + CONTROL + SHIFT + C", hl.dsp.exec_cmd(ipc .. "panel-toggle oldirtty/color_picker:panel"))

-- Move focus and resize (resize needs repeating)
hl.bind(mainMod .. " + right", hl.dsp.window.resize({ x = 50, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + left", hl.dsp.window.resize({ x = -50, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + up", hl.dsp.window.resize({ x = 0, y = -50, relative = true }), { repeating = true })
hl.bind(mainMod .. " + down", hl.dsp.window.resize({ x = 0, y = 50, relative = true }), { repeating = true })

if USE_HY3 then
    hl.bind(mainMod .. " + h", hy3.move_focus("l", { wrap = false }))
    hl.bind(mainMod .. " + l", hy3.move_focus("r", { wrap = false }))
    hl.bind(mainMod .. " + k", hy3.move_focus("u", { wrap = false }))
    hl.bind(mainMod .. " + j", hy3.move_focus("d", { wrap = false }))

    local function smart_move(dir)
        return function()
            local win = hl.get_active_window() -- confirm exact call in your hl version
            if win and win.floating then
                hl.dispatch(hl.dsp.window.move({
                    x = dir == "l" and -50 or dir == "r" and 50 or 0,
                    y = dir == "u" and -50 or dir == "d" and 50 or 0,
                    relative = true,
                }))
            else
                hl.dispatch(hy3.move_window(dir, { once = true }))
                update_borders()
            end
        end
    end

    hl.bind(mainMod .. " + SHIFT + h", smart_move("l"), { repeating = true })
    hl.bind(mainMod .. " + SHIFT + l", smart_move("r"), { repeating = true })
    hl.bind(mainMod .. " + SHIFT + k", smart_move("u"), { repeating = true })
    hl.bind(mainMod .. " + SHIFT + j", smart_move("d"), { repeating = true })

    hl.bind(mainMod .. " + apostrophe", hy3.toggle_focus_layer())
else
    hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "l" }))
    hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "r" }))
    hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "u" }))
    hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "d" }))

    hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.move({ direction = "l" }))
    hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.move({ direction = "r" }))
    hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.move({ direction = "u" }))
    hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.move({ direction = "d" }))
end

-- Workspace bindings
local k = { m = 1, comma = 2, period = 3, j = 4, k = 5, l = 6, u = 7, i = 8, o = 9 }
for key, num in pairs(k) do
    hl.bind(wmMod .. " + " .. key, hl.dsp.focus({ workspace = num }))
    -- hl.bind(wmMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = num }))
    hl.bind(wmMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = num }))
end

hl.bind(wmMod .. " + backspace", hl.dsp.workspace.toggle_special(""))
hl.bind(wmMod .. " + SHIFT + backspace", hl.dsp.window.move({ workspace = "special" }))

local dragBind = hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
local reiszeBind = hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

local function updateDragBind(w)
    local enabled = w ~= nil and w.fullscreen == 0
    dragBind:set_enabled(enabled)
    reiszeBind:set_enabled(enabled)
end
hl.on("window.active", updateDragBind)
hl.on("window.fullscreen", updateDragBind)

-- hl.on("workspace.active", update_borders)
-- hl.on("window.move_to_workspace", update_borders)
hl.on("window.open", function()
    hl.timer(function()
        update_borders()
    end, { timeout = 1, type = "oneshot" })
end)
hl.on("window.destroy", update_borders)
hl.on("window.active", update_borders)

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(ipc .. "brightness-up 10"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(ipc .. "brightness-down 10"), { repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Prevent the KDE Connect background window from stealing fullscreen focus
hl.window_rule({
    match = { class = "org.kde.kdeconnect.daemon" },
    suppress_event = "fullscreen",
    no_initial_focus = true,
    border_size = 0,
    float = true,
    move = { 0, 0 },
    size = { 1920, 1080 },
})

-- HyprMod managed settings
require("hyprland-gui")
