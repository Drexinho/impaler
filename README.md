# Impaler

A tiny macOS menu-bar app that pins any window of any app so it stays on top.

macOS does not let one app raise another app's window level. Impaler works around that without disabling SIP: the real window stays where it is, and whenever it loses focus a floating live mirror of it (ScreenCaptureKit) is shown at exactly the same place. Click the mirror and the real window comes forward and receives the click.

About 400 lines of Swift, AppKit only, no dependencies. The menu is in Czech.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`); full Xcode is not needed

## Build and run

```sh
./build.sh          # swift build -c release → Impaler.app, ad-hoc signed
open Impaler.app
```

## Permissions

Impaler needs two permissions in **System Settings › Privacy & Security**:

| Permission | Used for |
|---|---|
| Accessibility | following the pinned window's position and size, bringing it forward |
| Screen & System Audio Recording | the live image of the pinned window |

Grant both, then quit and reopen the app.

The build is ad-hoc signed, so macOS treats every rebuild as a new app and asks for the permissions again. If the toggles are on but nothing works after a rebuild, reset them and grant again:

```sh
tccutil reset Accessibility eu.drexinho.impaler
tccutil reset ScreenCapture eu.drexinho.impaler
```

## Usage

- Click the pin in the menu bar and choose **Připnout okno** (pin a window). Move the mouse over a window, which gets a blue outline, and click. Esc cancels.
- Repeat to pin more windows. The menu lists them in priority order: the first one is always in front of the others. Each entry has a submenu with **Posunout nahoru** (move up), **Posunout dolů** (move down) and **Odepnout** (unpin).
- A pinned window carries a 📌 badge in its top-right corner. Click the badge to unpin it. **Odepnout vše** unpins everything.

## How it works

1. **Picker** – a transparent overlay on every screen uses `CGWindowListCopyWindowInfo` to find the topmost window under the cursor.
2. **Tracking** – an `AXObserver` on the window reports moves, resizes, focus changes and destruction.
3. **Mirror** – an `SCStream` with `SCContentFilter(desktopIndependentWindow:)` captures the window even when it is covered. The frames are shown in a borderless floating `NSPanel` whenever the pinned window is not the focused window of the frontmost app.
4. **Click-through** – a click on the mirror activates the real window, waits until it has focus, and then replays the click at the same spot.

## Cost

Measured with one pinned window on an M4 Max: Impaler takes 3–6 % of one CPU core and 17 MB of memory, and the system capture daemon (`replayd`) another 1.5–2 %.

## Limitations

- The mirror forwards left clicks only. Dragging, right-clicking and scrolling over the mirror do nothing until the real window is in front.
- Minimised or hidden windows are not handled; the mirror stays at the last position.
- The capture stream keeps running at 60 fps while the mirror is hidden.
- The CGWindowID ↔ AX element lookup uses the private `_AXUIElementGetWindow` function, with a frame-matching fallback. This rules out the Mac App Store.

## Licence

[GPL-3.0](LICENSE)
