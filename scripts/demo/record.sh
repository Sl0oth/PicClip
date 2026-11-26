#!/bin/bash
# Re-records the README GIFs and stills into docs/media/. Hands off the mouse/keyboard while it runs (~1.5 min).
# Needs: Terminal allowed in Privacy & Security → Screen Recording and → Accessibility; Terminal not full screen;
# PicClip installed in /Applications; a 1728×1117-point main display (coordinates below are tuned for it).
# Everything it changes is undone at the end (also on Ctrl-C).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/media"; RAW="$OUT/raw"; mkdir -p "$RAW"
T="$(mktemp -d)"; MARK="$T/marker"; touch "$MARK"
ORIG_FRAME="$(defaults read app.picclip.PicClip "NSWindow Frame PicClipLibrary" 2>/dev/null || true)"

echo "Compiling helpers…"
for t in stage fakeshots drive hideall; do swiftc -O -swift-version 5 -o "$T/$t" "$ROOT/scripts/demo/$t.swift"; done

restore() {
    pkill -f "$T/stage" 2>/dev/null || true
    rm -f "$HOME/Desktop/Screenshot demo "*.png
    find "$HOME/Desktop" -maxdepth 1 -name "Screenshot *.png" -newer "$MARK" -delete
    osascript -e 'quit app "PicClip"' 2>/dev/null || true; sleep 1.5
    defaults delete app.picclip.PicClip DemoMode 2>/dev/null || true
    if [ -n "$ORIG_FRAME" ]; then defaults write app.picclip.PicClip "NSWindow Frame PicClipLibrary" "$ORIG_FRAME"; fi
    open /Applications/PicClip.app
    "$T/hideall" show
    echo "Restored."
}
trap restore EXIT

# Demo setup: fake screenshots on the Desktop, PicClip shows only those + new captures, backdrop over all windows.
"$T/fakeshots" "$HOME/Desktop" >/dev/null
defaults write app.picclip.PicClip DemoMode -bool true
defaults write app.picclip.PicClip "NSWindow Frame PicClipLibrary" "478 140 1000 640 0 0 1728 1085 "
osascript -e 'quit app "PicClip"'; sleep 1.5; open /Applications/PicClip.app; sleep 2
echo poster > "$T/scene"; ("$T/stage" "$T/scene" >/dev/null 2>&1 &); sleep 2.5

scene() { echo "$1" > "$T/scene"; sleep 0.8; }
capture() { # unrecorded ⇧⌘4 of the card on screen: capture x1 y1 x2 y2
    "$T/drive" <<EOF
move $(($1 - 8)) $(($2 - 8)) 200
key cmd+shift+4
wait 500
move $1 $2 200
down
drag $3 $4 500
up
wait 1500
move 1100 600 300
EOF
}
rec() { rm -f "$RAW/$2.mov"; screencapture -v -k -V"$1" -R448,217,1280,900 "$RAW/$2.mov" & sleep 1; "$T/drive"; wait; }

echo "Recording capture…"
rec 10 capture <<'EOF'
wait 600
move 740 400 500
key cmd+shift+4
wait 500
move 752 412 400
down
drag 1308 768 1200
up
wait 1600
win 4 110 70 800
wait 1800
move 1150 560 700
wait 600
EOF

echo "Recording drag…"; scene chat
rec 7 drag <<'EOF'
wait 600
win 4 110 70 700
wait 500
down
drag 1000 650 1500
wait 200
up
wait 2000
EOF

echo "Recording pin…"; scene poster; capture 752 412 1308 768; scene payment
rec 12 pin <<'EOF'
wait 500
win 4 110 70 700
wait 500
win 4 -18 -18 500
wait 250
click
wait 1400
win 3 160 120 700
wait 200
down
drag 1050 330 1300
up
wait 700
win 3 18 18 700
wait 600
click
wait 1000
EOF

echo "Recording edit…"; capture 728 388 1312 748
ELLIPSE=$(python3 -c "
import math
cx,cy,rx,ry=1393,684,42,17
pts=[(cx+rx*math.cos(t),cy+ry*math.sin(t)) for t in [-math.pi/2 + i*2*math.pi/22 for i in range(25)]]
print('move %d %d 600' % pts[0]); print('down')
for x,y in pts[1:]: print('drag %d %d 45' % (x,y))
print('up')")
rec 19 edit <<EOF
wait 500
win 4 110 70 700
wait 400
click
wait 1900
key r
wait 300
move 1106 604 700
down
drag 1270 629 700
up
wait 500
key b
wait 300
move 1106 576 500
down
drag 1288 601 700
up
wait 700
key p
wait 300
move 1106 632 500
down
drag 1268 657 700
up
wait 500
key m
wait 400
$ELLIPSE
wait 700
key cmd+s
wait 1600
key v
wait 400
move 1600 250 300
EOF

echo "Stills…"
WID=$(swift -e 'import CoreGraphics; for w in CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]] where (w[kCGWindowOwnerName as String] as? String) == "PicClip" && (w[kCGWindowLayer as String] as? Int) == 2 { print(w[kCGWindowNumber as String]!) }' 2>/dev/null | head -1)
screencapture -x -l"$WID" "$OUT/library.png"
echo "  (menu.png is captured by hand: it needs other menu bar icons masked out)"

echo "Converting to GIFs…"
for c in capture drag pin edit; do swift "$ROOT/scripts/make-gif.swift" "$RAW/$c.mov" "$OUT/$c.gif" 880 15 0.6 2>/dev/null; done
