#!/bin/sh

first=""
bluetoothctl devices Paired |
while read -r data
do
    uuid=`echo $data | cut -f2 -d' '`
    name=`echo $data | cut -f3- -d' '`

    info=`bluetoothctl info $uuid`
    if echo "$info" | grep -q "Connected: yes"; then
        echo -n "$first$name"
        first=" "
    fi
done
