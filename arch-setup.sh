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

create_symlink ghostty ~/.config/ghostty
create_symlink tmux ~/.config/tmux
create_symlink fish ~/.config/fish
create_symlink nvim ~/.config/nvim

create_symlink metapac ~/.config/metapac

create_symlink hypr ~/.config/hypr
# create_symlink sway ~/.config/sway
create_symlink noctalia ~/.config/noctalia

create_symlink kanata ~/.config/kanata
sudo_create_symlink kanata/kanata.service /lib/systemd/system/kanata.service
sudo systemctl enable kanata

