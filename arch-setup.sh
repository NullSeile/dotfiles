#!/bin/env bash

cd "$(dirname $0)"
dir=`pwd`

function create_symlink() {
    if [ -e "$2" ]; then
        echo "File '$2' already exists."
        rm -ri "$2"
    fi
    ln -s "$dir/$1" "$2"
}
function sudo_create_symlink() {
    if [ -e "$2" ]; then
        echo "File '$2' already exists."
        sudo rm -ri "$2"
    fi
    sudo ln -s "$dir/$1" "$2"
}

create_symlink nvim ~/.config/nvim
create_symlink tmux ~/.config/tmux

create_symlink wezterm ~/.config/wezterm
create_symlink kitty ~/.config/kitty

create_symlink metapac ~/.config/metapac

create_symlink hypr ~/.config/hypr
create_symlink waybar ~/.config/waybar
create_symlink rofi ~/.config/rofi

create_symlink kanata ~/.config/kanata
sudo_create_symlink kanata/kanata.service /lib/systemd/system/kanata.service
sudo systemctl enable kanata

# create_symlink i3 ~/.config/i3
# create_symlink polybar ~/.config/polybar
# create_symlink picom ~/.config/picom

