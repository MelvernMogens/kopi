# Kopi

A clipboard manager for macOS that does what CopyClip 2 does, in a small dropdown that doesn't hurt to look at.

![type](Resources/icon-1024.png)

## Why
CopyClip 2 works but its UI is rough. Kopi keeps every behaviour worth keeping — menu-bar dropdown, ⌃Space, ⌘1-0 quick paste, pins, direct paste, private mode, app ignore-list — and replaces the chrome: compact dark rows, source-app icons, live filter chips, instant fuzzy search with highlight, a quick preview on Space, and a proper edit sheet.

## How it works
```
NSPasteboard (poll 0.35s changeCount) ─▶ ClipboardMonitor ─▶ SQLite (WAL)
                                                              │
⌃Space / menu-bar icon ─▶ PanelController (NSPanel, dropdown)─┘
Enter / ⌘1-0 ─▶ pasteboard write + CGEvent ⌘V into previous app
CopyClip 2 ~/Library/.../copyclip.sqlite ──(read-only temp copy)──▶ import on first launch
```

**Honest limits:** text and rich text only (no image/file clips yet). Direct paste needs Accessibility permission. The pop-up-menu mode activates Kopi briefly, so it can flash in the Dock if you stare. Not sandboxed, not notarized — it's for one Mac.

## Build
```bash
swift test                    # 22 tests
scripts/make-signing-identity.sh   # once: stable identity so the Accessibility grant survives rebuilds
scripts/build-app.sh --install
```

## Shortcuts
| Keys | Action |
|---|---|
| ⌃Space / ⌃⇧Space | Panel / pop-up menu (CopyClip's defaults, carried over on first launch) |
| ↑↓ · ↩ | Navigate · paste (⇧↩ plain text) |
| ⌘1-⌘0 | Paste that row |
| Space | Full-clip preview · ⌘\ side preview pane |
| ⌘P · ⌘E · ⌘⌫ | Pin · edit · delete |
| ⇥ | Cycle filter chips |

## Roadmap
Image + file clips · richer RTF handling · pinned-section drag reorder.
