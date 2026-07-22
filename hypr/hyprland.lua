------------------
---- MONITORS ----
------------------

-- hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "auto", scale = "auto" })
hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "auto", scale = "auto" })
-- hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "auto", scale = "auto" })
hl.monitor({
    output = "HDMI-A-1",
    mode = "highrr",
    position = "auto-left",
})
-- hl.monitor({
--     output = "HDMI-A-1",
--     mode = "1920x1080@60",
--     position = "auto",
--     mirror = "eDP-1",
-- })

-- For Noctalia Color templates
local noctalia = require("noctalia")
local colors = noctalia.colors
noctalia.apply_theme()

hl.config({
    debug = { suppress_errors = false },
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
local browser = "zen-browser"
local fileManager = "nautilus"
local menu = ipc .. "panel-toggle launcher"
-- local menu = "walker"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("otd-daemon")
    hl.exec_cmd("syncthing --no-browser")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("hyprpm reload -n")
    hl.exec_cmd("swaybg -i /home/lia/dotfiles/himawari-wallpaper/lastest.png -m fill")
    -- hl.exec_cmd("qs -c noctalia-shell")
    hl.exec_cmd("noctalia")
    hl.exec_cmd("systemctl --user start himawari.service")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("walker --gapplication-service")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- hl.env("XCURSOR_SIZE", "24")
-- hl.env("HYPRCURSOR_SIZE", "24")
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

hl.config({
    cursor = { no_hardware_cursors = true },

    general = {
        snap = { enabled = true },
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        resize_on_border = true,
        allow_tearing = false,
        layout = USE_HY3 and "hy3" or "dwindle",
    },

    decoration = {
        rounding = 5,
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
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 0,
        float_switch_override_focus = 0,
        sensitivity = 0,
        touchpad = {
            scroll_factor = 1,
            natural_scroll = true,
            disable_while_typing = false,
        },
    },
})

if USE_HY3 then
    hl.config({
        plugin = {
            hy3 = {
                tabs = {
                    render_text = false,
                    padding = 5,
                    border_width = 0,
                    height = 8,
                    colors = {
                        active = colors.secondary,
                        active_alt_monitor = colors.primary,
                        focused = colors.primary,
                        inactive = colors.surface,
                        urgent = colors.error,
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
hl.bind(mainMod .. " + SHIFT + SPACE", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + CONTROL + SPACE", hl.dsp.exec_cmd(menu))

-- Fullscreen dispatcher does not have a native dsp yet, fallback to exec_cmd with hyprctl
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + Z", hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" }))

-- hy3 specific dispatchers or dwindle fallback
if USE_HY3 then
    hl.bind(mainMod .. " + W", hy3.change_group("toggletab"))
else
    hl.bind(mainMod .. " + W", hl.dsp.group.toggle())
    hl.bind(mainMod .. " + S", hl.dsp.layout("togglesplit"))
end

hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(ipc .. "screenshot-region"))
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

    hl.bind(mainMod .. " + SHIFT + h", hy3.move_window("l"))
    hl.bind(mainMod .. " + SHIFT + l", hy3.move_window("r"))
    hl.bind(mainMod .. " + SHIFT + k", hy3.move_window("u"))
    hl.bind(mainMod .. " + SHIFT + j", hy3.move_window("d"))
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
    hl.bind(wmMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = num }))
end

hl.bind(wmMod .. " + backspace", hl.dsp.workspace.toggle_special(""))
hl.bind(wmMod .. " + SHIFT + backspace", hl.dsp.window.move({ workspace = "special" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

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
