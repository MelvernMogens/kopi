#!/bin/bash
# Drives the running Kopi panel with real keystrokes. Refuses to type unless Kopi is frontmost.
# Usage: scripts/ui-drive.sh <out-prefix> <step>...   steps: type:TEXT  key:CODE[:mods]  shot:NAME  sleep:S
set -u
OUT=${1:-/tmp/kd}; shift
front() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'; }
wid() { osascript -l JavaScript -e "ObjC.import('CoreGraphics'); var a=ObjC.deepUnwrap(ObjC.castRefToObject(\$.CGWindowListCopyWindowInfo(1,0))); a.filter(w=>w.kCGWindowOwnerName=='Kopi' && w.kCGWindowLayer>0).map(w=>w.kCGWindowNumber)[0]"; }
guard() { local f; f=$(front); if [ "$f" != "Kopi" ]; then echo "ABORT: frontmost is '$f', not Kopi"; exit 2; fi; }
for st in "$@"; do
  case "$st" in
    type:*) guard; osascript -e "tell application \"System Events\" to keystroke \"${st#type:}\"" ;;
    key:*) guard; IFS=: read -r _ code mods <<<"$st"
      if [ -n "${mods:-}" ]; then osascript -e "tell application \"System Events\" to key code $code using {$mods}"
      else osascript -e "tell application \"System Events\" to key code $code"; fi ;;
    shot:*) W=$(wid); if [ -z "$W" ]; then echo "no panel window for ${st#shot:}"; continue; fi
      screencapture -o -l "$W" "$OUT-${st#shot:}.png" && sips -s format jpeg "$OUT-${st#shot:}.png" --out "$OUT-${st#shot:}.jpg" >/dev/null && echo "shot $OUT-${st#shot:}.jpg" ;;
    sleep:*) sleep "${st#sleep:}" ;;
  esac
  sleep 0.35
done
echo "front now: $(front)"
