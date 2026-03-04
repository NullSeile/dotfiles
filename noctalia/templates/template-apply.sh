#!/usr/bin/env -S bash

# Ensure at least one argument is provided.
if [ "$#" -lt 1 ]; then
    # Print usage information to standard error.
    echo "Error: No application specified." >&2
    echo "Usage: $0 {hy3} [dark|light]" >&2
    exit 1
fi

APP_NAME="$1"
MODE="${2:-}" # Optional second argument for dark/light mode

# --- Apply theme based on the application name ---
case "$APP_NAME" in
hy3)
    echo "🎨 Applying 'noctalia' theme to Hyprland..."
    CONFIG_DIR="$HOME/.config/hypr"
    CONFIG_FILE="$CONFIG_DIR/hyprland.conf"
    THEME_FILE="$CONFIG_DIR/noctalia/noctalia-hy3-colors.conf"

    INCLUDE_LINE="source = $THEME_FILE"

    # Check if the config file exists.
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file not found, creating $CONFIG_FILE..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo -e "\n$INCLUDE_LINE\n" >"$CONFIG_FILE"
        echo "Created new config file with noctalia theme."
    else
        if [ -L "$CONFIG_FILE" ] && [ ! -w "$CONFIG_FILE" ]; then
            echo "Detected read-only symlink, converting to local file..."
            cp --remove-destination "$(readlink -f "$CONFIG_FILE")" "$CONFIG_FILE"
            chmod +w "$CONFIG_FILE"
        fi

        # Check if noctalia theme source already exists (flexible matching)
        if grep -qE 'source\s*=\s*.*noctalia-hy3.*\.conf' "$CONFIG_FILE"; then
            echo "Theme already included, skipping modification."
        else
            # Add the include line to the end of the file
            echo -e "\n$INCLUDE_LINE\n" >>"$CONFIG_FILE"
            echo "✅ Added noctalia theme include to config."
        fi
    fi

    # Reload hyprland
    hyprctl reload
    ;;
esac
