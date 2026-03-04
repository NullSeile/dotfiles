set -gx EDITOR nvim
set -gx SHELL /usr/bin/fish

set -g fish_key_bindings fish_vi_key_bindings

function fish_user_key_bindings
    for mode in insert default visual
        bind -M $mode \cf forward-char
    end
end

function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

# pyenv init - fish | source
# status --is-interactive; and pyenv virtualenv-init - | source

# Restart your shell for the changes to take effect.
if status is-interactive
    # Commands to run in interactive sessions can go here
end
