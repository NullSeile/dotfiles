polybar-msg cmd quit

polybar --list-monitors | while IFS=$'\n' read line; do
  monitor=$(echo $line | cut -d':' -f1)
  primary=$(echo $line | cut -d' ' -f3)
  # MONITOR=$monitor polybar --reload "dummy" &
  MONITOR=$monitor polybar --reload "main" &
done
