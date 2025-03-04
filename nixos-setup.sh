#!/bin/env bash

cd "$(dirname $0)"
dir=`pwd`

function create_symlink() {
    if [ -e "$2" ]; then
        echo "Removing $2"
        rm -ri "$2"
    fi
    ln -s "$dir/$1" "$2"
}


function sudo_create_hardlink() {
    if [ -e "$2" ]; then
        echo "Removing $2"
        sudo rm -ri "$2"
    fi
    sudo ln "$dir/$1" "$2"
}

sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos-unstable
sudo nix-channel --update

sudo_create_hardlink nixos/configuration.nix /etc/nixos/configuration.nix

create_symlink i3 ~/.config/i3
create_symlink nvim ~/.config/nvim


sudo_create_hardlink kanata/fancy.kbd /etc/nixos/kanata.kbd

create_symlink wezterm ~/.config/wezterm
create_symlink polybar ~/.config/polybar
create_symlink picom ~/.config/picom

