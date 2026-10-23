# kopi

## What this is
Kopi is Melvern's clipboard manager for macOS — a copy of CopyClip 2's feature set with a UI that doesn't suck: a small dark dropdown under the menu-bar icon, search with filters, pins, edit, quick preview. Runs from the menu bar (LSUIElement). Personal app, not distributed.

## Stack
- Swift Package (no Xcode project): `KopiKit` (pure logic + SQLite via C API, unit tested) + `Kopi` executable (AppKit panel + SwiftUI content). Zero dependencies.
- Carbon `RegisterEventHotKey` for global hotkeys; CGEvent for paste-on-select (needs Accessibility).
- SQLite store at `~/Library/Application Support/Kopi/kopi.sqlite` (WAL). Imports CopyClip 2's Core Data db read-only (temp copy, so a running CopyClip is never touched).
- Rejected: Maccy/Raycast-style big panel (Melvern wanted CopyClip's small dropdown under the icon); JSON store (search over 9,999 clips); Electron anything.

## Commands
```bash
swift build                     # debug build
swift test                      # 22 KopiKit tests
scripts/build-app.sh            # release -> build/Kopi.app (stable self-signed identity in ~/.kopi-signing)
scripts/build-app.sh --install  # copy to /Applications + launch
scripts/make-signing-identity.sh  # one-time; keeps the Accessibility grant across rebuilds
swift scripts/make-icon.swift   # regenerate Resources/AppIcon.icns
scripts/ui-drive.sh             # keystroke driver; refuses to type unless Kopi is frontmost
```

## Milestones — status
Scope, non-goals, open questions: `docs/prd.md`.

| # | Scope | Status |
|---|---|---|
| M1 | Record, search, pin, paste, dropdown UI, CopyClip import, settings | done |
| M2 | Verify hotkey/panel edge cases, quick-look + edit overlays, themes | done |
| M3 | Rich-text paste fidelity, image/file clips, menu-bar drag reorder | backlog |

## Conventions
- Ask before adding a dependency.
- Never commit secrets.
- UI taste (Melvern): compact rows, no big buttons, dark, minimal chrome. Match CopyClip's default shortcuts literally (⌃Space, ⌃⇧Space, ⌘1-0) — he uses them daily.

## House rules
- Run `swift test` before and after changes; report real results.
- After UI changes, verify with a real screenshot (`scripts/ui-drive.sh shot:`), not "should work".
- The debug env `KOPI_DEBUG=1` logs panel state to the console — use it before guessing at focus bugs. Known trap: System Events reports menu-bar apps as never "frontmost"; trust KOPI_DEBUG's key= instead.
