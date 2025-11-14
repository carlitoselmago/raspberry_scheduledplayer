#!/bin/bash
#
# Scheduled video player for Raspberry Pi
# Plays a video at specified times.
# Between plays, displays a black screen with "Next play" info.
#

setterm -blank force -powerdown 0 -cursor off > /dev/tty1 < /dev/tty1
clear > /dev/tty1

VIDEO="/home/pi/video.mp4"
SCHEDULE_FILE="/home/pi/video_schedule.txt"
LOG_FILE="/home/pi/scheduled_video.log"

#############################################
# Setup logging with timestamps and rotation
#############################################
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 500000 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    echo "=== Log rotated at $(date) ===" > "$LOG_FILE"
fi

# Simple log redirection (no awk strftime dependency)
exec >> "$LOG_FILE" 2>&1
echo "=== Script started at $(date) ==="

#############################################
# Functions
#############################################

# Compute next play time and human-readable countdown
next_play_info() {
    now=$(date +%s)
    next_time=""
    min_diff=$((24*60*60))  # 1 day in seconds

    while IFS=: read -r h m; do
        [[ -z "$h" ]] && continue
        target=$(date -d "$(date +%F) $h:$m" +%s)
        if (( target < now )); then
            target=$((target + 24*60*60))  # shift to next day
        fi
        diff=$((target - now))
        if (( diff < min_diff )); then
            min_diff=$diff
            next_time="$h:$m"
        fi
    done < "$SCHEDULE_FILE"

    hours=$((min_diff / 3600))
    mins=$(((min_diff % 3600) / 60))
    echo "$next_time ($hours h $mins m)"
}

# Create black screen with white text showing next play info
show_next_screen() {
    info=$(next_play_info)
    echo "Next play: $info"

    convert -size 1920x1080 xc:black \
        -fill white -gravity center \
        -pointsize 60 -annotate +0-100 "Pròxima projecció" \
        -pointsize 120 -annotate +0+0 "${info%% (*}" /tmp/next_play.jpg
        #-pointsize 120 -annotate +0+0 "${info%% (*}" \
        #-pointsize 40 -annotate +0+150 "${info#* }" /tmp/next_play.jpg

    # Stop any previous viewers
    pkill fim 2>/dev/null

    # Display new info screen silently on HDMI (tty1)
    sudo fim -a --quiet --vt 1 /tmp/next_play.jpg >/dev/null 2>&1 &
}

#############################################
# Initial black screen
#############################################
show_next_screen

#############################################
# Main loop
#############################################
while true; do
    current_time=$(date +%H:%M)

    if grep -q "^$current_time$" "$SCHEDULE_FILE"; then
        echo "Playing video at $current_time"
        pkill fim 2>/dev/null  # clear info screen

        # PRE-PLAY: force-clear framebuffer (no flash of old image)
        sudo sh -c 'cat /dev/zero > /dev/fb0' 2>/dev/null
        sleep 0.05

        # Play video
        omxplayer -b --no-osd "$VIDEO"

        # POST-PLAY: force-clear framebuffer again so old schedule never flashes
        sudo sh -c 'cat /dev/zero > /dev/fb0' 2>/dev/null
        sleep 0.05

        # Now show NEW schedule info
        show_next_screen
        sleep 60
    else
        sleep 5
    fi


done

