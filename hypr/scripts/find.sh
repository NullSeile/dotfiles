#!/bin/bash

selection=$(find ~/ \
	# -wholename '/home/lia/.cache' -prune -o \
	# -wholename '/home/lia/.local' -prune -o \
	# -wholename '/home/lia/MATLAB' -prune -o \
	# -wholename '/home/lia/.MathWorks' -prune -o \
	# -wholename '/home/lia/V/Keyboard/qmk_firmware' -prune -o \
	# -wholename '/home/lia/Downloads/matlab' -prune -o \
	-type f \
	-print \
	| fzf)
xdg-open "$selection"
disown

