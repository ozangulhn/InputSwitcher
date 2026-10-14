# Input Switcher

A menu bar display input switcher for Apple Silicon Macs. It switches an external monitor's input over DDC/CI using the [`m1ddc`](https://github.com/waydabber/m1ddc) CLI. No BetterDisplay needed, completely free.

Current version: `1.7.1` · [Releases](https://github.com/ozangulhn/InputSwitcher/releases)

The app UI is available in English and Turkish. It follows the macOS language by default; switch it under **Language** in the menu (System / Türkçe / English).

## Features

- Switch inputs from the menu, with a cycle shortcut, or with a dedicated global hotkey per input
- Per-input nicknames, raw DDC values and DDC command mode
- Brightness and volume sliders, plus optional keyboard-key control
- Two-Mac setup: the Macs find each other over Bonjour and forward switch requests
- Input discovery, diagnostics log and in-app updates

---

## Installation

### Install from source

1. Download or clone this repo
2. Double-click `install.command` in Finder

Or from Terminal:

```bash
chmod +x install.sh
./install.sh
```

The script:

1. Checks that you are on Apple Silicon and that the Swift compiler is available (otherwise it starts the Xcode Command Line Tools install and asks you to run it again)
2. Looks for `m1ddc` in `/opt/homebrew/bin`, `/usr/local/bin` and `PATH`; if missing, installs it with Homebrew, or builds it from source into `/usr/local/bin` (needs `sudo`)
3. Builds the app with `build_app.sh`
4. Quits a running copy and replaces any existing install at `~/Applications/InputSwitcher.app`
5. Optionally adds it as a login item
6. Optionally launches it

The generated app bundle includes the local network and Bonjour entries (`NSLocalNetworkUsageDescription`, `_inputswitcher._tcp`) needed to find the other Mac on the LAN.

Running `install.command` again later replaces the installed app with the new version. The script prompts are in Turkish; answer `e` for yes.

### Build a DMG and ZIP

Double-click `build_dmg.command` (or run `./build_dmg.sh`). This does not touch the installed app. Output:

- `dist/InputSwitcher-<version>.dmg`
- `dist/InputSwitcher-<version>.zip`

### Gatekeeper

Apps installed from a downloaded zip or DMG are ad-hoc signed, so macOS may block the first launch. Either:

- Open **System Settings → Privacy & Security** and click **Open Anyway**, or
- Remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/InputSwitcher.app
```

Installs done with `install.command` and in-app updates are not affected.

---

## Usage

Click the display icon in the menu bar, pick an input, and the monitor switches. The active input is highlighted in blue and checked in the list.

### Menu

| Item | What it does |
|------|--------------|
| Input list | Switches to the selected input |
| Brightness and volume sliders | Adjust the monitor over DDC while it is attached to this Mac. Click the speaker icon to mute/unmute |
| Cycle selected inputs | Steps through inputs marked **In Cycle**; shows the cycle shortcut if one is set |
| Refresh Current Input | Re-reads the monitor's active input |
| On screen: ... | Shows which Mac currently owns the monitor |
| Show On-Screen Mac in Menu Bar | Shows that Mac's name in the menu bar as well |
| Keyboard Keys | Lets the Mac's media keys control the monitor (see below) |
| Edit Input List... | Opens the input editor |
| Language | System / Türkçe / English |
| Updates | Automatic update checks and installs (see below) |
| About | Version, install path, and a note about installing on both Macs |
| Diagnostics Log | Peer discovery, display ownership and switch requests |
| Quit | Exits the app |

### Keyboard keys

Under **Keyboard Keys**:

- **Brightness keys control the external display**: while the pointer is on the external display, the brightness keys adjust it over DDC
- **Volume keys control the display speakers**: while the display is attached to this Mac, the volume and mute keys control its speakers over DDC
- Hold Option+Shift for fine steps

This needs the macOS **Accessibility** permission (the menu shows **Accessibility permission needed...** until it is granted). The app is ad-hoc signed, so the signature changes on every reinstall or update and you may have to grant the permission again under System Settings → Privacy & Security → Accessibility.

### Editing the input list

Open **Edit Input List...** (Cmd+,). For each input you can set:

- **Nickname**: add, change, or clear it by leaving the field empty
- **DDC value** and **DDC command**: `Auto`, `input`, or `input-alt (LG)`. Use **Test** on a row to try the value and command immediately
- **In Cycle**: include the input in the cycle shortcut
- **Hotkey**: a dedicated global shortcut that switches straight to this input. Shortcuts need at least one of Cmd, Ctrl or Option; Esc cancels recording and Delete clears it. The same shortcut can't be used in two places

Other controls:

- **Display**: choose the target monitor
- **Cycle Shortcut**: a global shortcut that cycles only through inputs marked **In Cycle**
- **Discover Inputs...**: see below
- **Open Log**: opens the diagnostics log

With `Auto`, a display whose name contains "LG" is sent `input-alt` with the LG equivalents of the default values.

### Discover Inputs

**Discover Inputs...** tries common `input` and `input-alt` values one by one. If the screen switches away, the app switches back automatically (directly or through the other Mac). When it finishes, **Apply to List** copies the working values into the list; press **Save** to keep them. If the screen gets stuck on an empty input, press the monitor's own input button to return to this Mac.

### Two Macs on one monitor

With Input Switcher installed on both Macs, they find each other over Bonjour on the local network.

- If the monitor is not attached to this Mac, a switch request is forwarded to the Mac that owns it
- The **On screen:** line shows which Mac currently has the monitor
- The app learns which Mac is on which input (after two stable readings) and shows `◦ Mac name` next to inputs that have no nickname
- Ownership is decided from the real `m1ddc display list` result; there is no fake display fallback
- Peers are matched by a normalized monitor identity, not the raw display title
- Once a Mac leaves the monitor it can no longer send a command to the display itself, so it can only switch back through the other Mac. That is why the app needs to be on both Macs

### Diagnostics

**Diagnostics Log** records peer discovery, monitor ownership and switch requests. Use **Copy All** to copy the whole log.

---

## Updates

The app finds new releases on GitHub Releases and updates itself in place.

- It checks about 10 seconds after launch and every 6 hours (**Updates > Automatically check for updates**, on by default). Use **Check for Updates...** to check manually
- When a new version exists, **Update available: x.y.z — Install** appears at the top of the menu, and a one-time alert is shown for each new version
- **Install** downloads `InputSwitcher-<version>.zip`, validates it (bundle identifier and version), quits the app, swaps in the new version and relaunches it. Progress shows in the menu title
- **Install updates automatically** (off by default) installs found updates without asking
- If the app's folder isn't writable, the release page opens so you can install manually
- Because the app is ad-hoc signed, macOS may ask for the Accessibility permission again after an update (keyboard keys feature)
- The repository must be public, otherwise other Macs can't see releases. The repository name is the `updateRepository` constant in `InputSwitcher.swift`

## Publishing a release

1. Bump the version in `VERSION` and commit (the working tree must be clean)
2. Double-click `release.command`, or run:

```bash
./release.sh [notes.md]
```

The script builds the ZIP and DMG, shows a summary, and after you confirm, tags `v<version>`, pushes, and creates the GitHub Release with both files. Without a notes file, release notes are generated automatically.

Requirements: an `origin` remote, and the GitHub CLI (`gh`) installed and signed in with `gh auth login`.

Other Macs pick up the new version at their next update check.

---

## Input values

Default DDC values (these can differ per monitor):

| Source        | DDC value |
|---------------|-----------|
| DisplayPort 1 | 15        |
| DisplayPort 2 | 16        |
| HDMI 1        | 17        |
| HDMI 2        | 18        |
| USB-C         | 27        |

To find your own monitor's values, run this on each Mac while it is the active input:

```bash
m1ddc get input
```

You can change names and values in **Edit Input List...**. Homebrew's `m1ddc` is normally at `/opt/homebrew/bin/m1ddc` on Apple Silicon; the app finds it automatically.

### LG monitors (`input-alt`)

LG monitors don't fully support standard DDC/CI input switching. Use `input-alt (LG)` with these values:

| Source        | `input-alt` value |
|---------------|-------------------|
| DisplayPort 1 | 208               |
| DisplayPort 2 | 209               |
| HDMI 1        | 144               |
| HDMI 2        | 145               |
| USB-C         | 210               |

On LG models with a single DisplayPort (e.g. LG HDR 4K / 27UL850), USB-C is usually **209** instead of 210 (m1ddc lists 209 as "DisplayPort 2"). If USB-C doesn't switch, try 209.

---

## Requirements

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 12 Monterey or later
- A monitor with DDC/CI support
- Connection over USB-C or DisplayPort (the built-in HDMI port on M1/M2 Macs is not supported)
- To build from source: Xcode Command Line Tools (`swiftc`)

---

## Troubleshooting

**Switching doesn't work:** check whether the monitor supports DDC/CI:

```bash
m1ddc display list
```

**LG monitor:** try the `input-alt` values above (or leave the command on `Auto`).

**M1 Mac mini / built-in HDMI:** the built-in HDMI port isn't supported; use a USB-C adapter.

**"m1ddc not found" in the menu:** install it with Homebrew (`brew install m1ddc`) or choose **Show install instructions** in the menu.
