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

create_symlink i3 ~/.config/regolith3/i3
create_symlink i3 ~/.config/i3

create_symlink nvim ~/.config/nvim

create_symlink kanata ~/.config/kanata
sudo_create_symlink kanata/kanata.service /etc/systemd/system/kanata.service
sudo systemctl enable kanata

create_symlink wezterm ~/.config/wezterm
create_symlink polybar ~/.config/polybar
create_symlink picom ~/.config/picom

