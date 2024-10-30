#!/bin/sh

# Rotatation
case $1 in
    1) xrandr --output HDMI-1 --rotate left ;;
    2) xrandr --output HDMI-1 --rotate right ;;
    3) xrandr --output HDMI-1 --rotate normal ;;
    4) xrandr --output HDMI-1 --rotate inverted ;;
esac

# Rotate Touchscreen
case $1 in 
    1) xinput set-prop '<touchscreen-name>' --type=float 'Coordinate Transformation Matrix' 0 -1 1 1 0 0 0 0 1 ;;
    2) xinput set-prop '<touchscreen-name>' --type=float 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1 ;;
    3) xinput set-prop '<touchscreen-name>' --type=float 'Coordinate Transformation Matrix' 1 0 0 0 1 0 0 0 1 ;;
    4) xinput set-prop '<touchscreen-name>' --type=float 'Coordinate Transformation Matrix' -1 0 1 0 -1 1 0 0 1 ;;
esac
