#!/usr/bin/env bash
cd "$(dirname "$0")"

# {n}.png, where n is the current frame
current=`ls | grep .png`

# Extract the number from the filename
number=`echo $current | sed 's/[^0-9]*//g'`

next=`expr $number + 1`

max_frame=`ls temp | wc -l`
if [ $next -gt $(($max_frame - 1)) ]; then
    next=0
fi

rm $current
cp temp/$next.png .

echo `pwd`/$next.png
