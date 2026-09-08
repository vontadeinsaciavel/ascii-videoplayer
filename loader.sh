# will need you to have ffmpeg and jp2a installed to work
# make this file executable with chmod +x command
# YOU WILL NEED TO HAVE YOUR VIDEO ON THE SAME FOLDER!!
# example (executing on terminal): ./ascii-badapple.sh badapple.mp4
# its possible to configure the width and fps to!!>> ./ascii-badapple.sh badapple.mp4 15 150 (15 fps)
# hope you like this!!
set -euo pipefail

export LC_ALL=C
 
if [ $# -lt 1 ]; then
  echo "Usage: $0 <video-file> [fps] [width] [height]"
  echo "  (width/height default to your current terminal size if omitted)"
  exit 1
fi
 
for cmd in ffmpeg ffplay jp2a; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is not installed or not on PATH."
    echo "Install ffmpeg via pacman, and jp2a via an AUR helper (e.g. 'yay -S jp2a')."
    exit 1
  fi
done
 
VIDEO="$1"
FPS="${2:-30}"

TERM_COLS=$(tput cols)
TERM_LINES=$(tput lines)

WIDTH="${3:-$TERM_COLS}"
HEIGHT="${4:-$((TERM_LINES - 1))}"
 
if [ ! -f "$VIDEO" ]; then
  echo "Error: video file '$VIDEO' not found."
  exit 1
fi
 
WORKDIR=$(mktemp -d)
FRAMES_DIR="$WORKDIR/frames"
ASCII_DIR="$WORKDIR/ascii"
AUDIO_FILE="$WORKDIR/audio.aac"
mkdir -p "$FRAMES_DIR" "$ASCII_DIR"
 
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT
 
echo "==> Extracting audio (if any)..."
ffmpeg -y -i "$VIDEO" -vn -acodec copy "$AUDIO_FILE" -loglevel error || true
 
echo "==> Extracting frames at ${FPS} fps..."
ffmpeg -y -i "$VIDEO" -vf "fps=${FPS}" "$FRAMES_DIR/frame_%05d.png" -loglevel error
 
FRAME_COUNT=$(find "$FRAMES_DIR" -name '*.png' | wc -l)
if [ "$FRAME_COUNT" -eq 0 ]; then
  echo "Error: no frames extracted. Check the video file."
  exit 1
fi
 
echo "==> Converting ${FRAME_COUNT} frames to ASCII (using $(nproc) cores)..."
export ASCII_DIR WIDTH HEIGHT
find "$FRAMES_DIR" -name '*.png' | sort | xargs -P "$(nproc)" -I{} bash -c '
  f="{}"
  base=$(basename "$f" .png)
  jp2a --width="$WIDTH" --height="$HEIGHT" "$f" > "$ASCII_DIR/$base.txt"
'
 
echo "==> Ready! Starting playback..."
sleep 1
 
# Play audio in background if we actually got one
if [ -s "$AUDIO_FILE" ]; then
  ffplay -nodisp -autoexit -loglevel quiet "$AUDIO_FILE" &
  AUDIO_PID=$!
fi

clear
tput civis  # hide cursor
 
start_us=${EPOCHREALTIME//[.,]/}
frame_num=0
for f in "$ASCII_DIR"/*.txt; do
  frame_num=$((frame_num + 1))
  target_us=$(( frame_num * 1000000 / FPS ))
  now_us=$(( ${EPOCHREALTIME//[.,]/} - start_us ))
  sleep_us=$(( target_us - now_us ))
 
  if (( sleep_us > 0 )); then
    sleep "$(printf '%d.%06d' $((sleep_us / 1000000)) $((sleep_us % 1000000)))"
  fi
 
  tput cup 0 0
  cat "$f"
done
tput cnorm
 
if [ -n "${AUDIO_PID:-}" ]; then
  wait "$AUDIO_PID" 2>/dev/null || true
fi
 
echo
echo "==> Done!!"
