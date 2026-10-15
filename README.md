# Dynis

A compact Dynamic Island for **Hyprland**, built with **Quickshell**, QML, and a Qt 6 backend. A small clock at rest, with animated transitions into media controls, notifications, workspace previews, and system status.

![Dynis application launcher over a desktop wallpaper](docs/images/launcher.jpg)

*Keyboard-driven application launcher, with the island tucked into the top edge.*

![Expanded Dynis preview showing workspaces, date, time, volume, CPU, and RAM](docs/images/island-preview.jpg)

*Expanded status preview with workspace indicators, volume, and CPU/RAM graphs.*

The screenshots show a customized desktop. Wallpaper and compositor effects are not bundled; fonts and appearance can differ from the defaults.

## What it does

- **Adaptive island** — clock, horizontal swipe views, volume/brightness feedback, recording indicator, and fullscreen-aware visibility.
- **System preview** — workspace indicators, date and time, volume status, and CPU/RAM usage with history graphs. Can be shown while holding Super using the bindings below.
- **Media** — MPRIS playback controls, track metadata, cover art, optional synced lyrics, and CAVA visualization.
- **Notifications** — desktop notification popups with application icons and image previews.
- **Workspaces** — per-monitor workspace strip and an overview for navigating windows and workspaces.
- **Connectivity** — Wi-Fi and Bluetooth views, with network selection and pairing controls.
- **Launcher and clipboard** — searchable application list, keyboard navigation, usage-based application ranking, and a cliphist picker.
- **Personalization** — watched JSON configuration, bundled Xanh Mono and Symbols Nerd Font, rounded screen corners, and edge shadows.

This is a personal desktop-shell project in active development. Some integrations depend on your compositor, hardware, permissions, and installed services. The former standalone control-center click actions are retained for compatibility but currently return the island to its resting state.

## Requirements

Run Dynis inside a **Hyprland Wayland session**. It is not a standalone desktop environment.

| Component | Purpose |
| --- | --- |
| Quickshell with Hyprland, Wayland, Bluetooth, MPRIS, and Notifications modules | QML shell runtime |
| Qt 6 development packages, CMake 3.16+, a C++17 compiler, libudev development files | Build the backend and helpers |
| Qt 6 Core, Gui, Qml, Network, DBus, Test, Concurrent | Modules required by the CMake build |
| `hyprctl`, `wpctl`, `pactl`, `brightnessctl` | Compositor, audio, and backlight integration |
| UPower and BlueZ | Battery and Bluetooth integration |

Optional integrations:

| Component | Enables |
| --- | --- |
| NetworkManager or iwd | Wi-Fi management |
| MPRIS-capable player | Media metadata and playback controls |
| `cava` | Audio visualizer |
| `cliphist` and `wl-clipboard` | Clipboard history and selection |
| ImageMagick | Wallpaper thumbnails |
| TLP | Power-profile backend where available |
| A compatible compositor glass plugin | Refraction and backdrop effects |

Package names vary by distribution. Quickshell and its Qt runtime must be compatible with the Qt version used to build Dynis.

## Build and try it

```bash
git clone https://github.com/fanat-sira/dynis.git
cd dynis
./scripts/install-fonts.sh
cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build-release -j2
ctest --test-dir build-release --output-on-failure
BUILD_DIR="$PWD/build-release" QUICKSHELL_LYRICS_BACKEND="$PWD/build-release/lyricsmpris" ./run-local.sh
```

The font script installs the bundled fonts for your user. `run-local.sh` loads the backend from the specified build directory; the lyrics environment variable selects the helper from that same build.

Run only one Dynis instance at a time. If you already use the installed service, stop it with `systemctl --user stop dynis` before trying the checkout.

Dynis owns `org.freedesktop.Notifications`. Stop any other notification daemon, such as dunst or mako, before starting it. Notification actions, inline replies, and persistent notification history are not currently advertised by the server.

### Install system-wide

After building with the `/usr` prefix above:

```bash
sudo cmake --install build-release
systemctl --user daemon-reload
systemctl --user enable --now dynis
```

QML files are installed to `/usr/share/dynis`, helper executables to `/usr/share/dynis/bin`, and bundled fonts to `/usr/share/fonts/dynis`. The launcher is `dynis`; the user service is `dynis.service`. Use `/usr` for installation: some helper and service paths still assume it.

Alternatively, start `dynis` from Hyprland:

```conf
exec-once = dynis
```

Choose either the service or `exec-once` to avoid duplicate instances.

### Debian / Ubuntu helper

An optional installer installs system dependencies, builds Quickshell if needed, builds Dynis, and starts the user service by default:

```bash
./scripts/install-debian-ubuntu.sh --help
# Review the script before running it; it installs packages using sudo.
./scripts/install-debian-ubuntu.sh --no-enable-service
```

Availability depends on your distribution's packages. This is not a promise of compatibility with every Debian or Ubuntu release.

## Hyprland bindings

Add the bindings you want to your Hyprland configuration. These examples assume `$mainMod` is already defined, usually as `SUPER`.

```conf
bind = $mainMod, M, exec, qs ipc -p /usr/share/dynis call dynis togglePlayer
bind = $mainMod, down, exec, qs ipc -p /usr/share/dynis call dynis showClock
bind = $mainMod, left, exec, qs ipc -p /usr/share/dynis call dynis showCustom
bind = $mainMod, right, exec, qs ipc -p /usr/share/dynis call dynis showLyrics
bind = $mainMod, TAB, exec, qs ipc -p /usr/share/dynis call overview toggle
bind = ALT, SPACE, exec, qs ipc -p /usr/share/dynis call dynis launcher
bind = $mainMod, V, exec, qs ipc -p /usr/share/dynis call dynis clipboard
bind = $mainMod, W, exec, qs ipc -p /usr/share/dynis call dynis showWifi
bind = $mainMod, B, exec, qs ipc -p /usr/share/dynis call dynis showBluetooth

# Show the status preview while holding the left Super key.
bind = $mainMod, SUPER_L, exec, qs ipc -p /usr/share/dynis call dynis mainModDown
bindr = $mainMod, SUPER_L, exec, qs ipc -p /usr/share/dynis call dynis mainModUp
```

For a local run, replace `/usr/share/dynis` with the absolute checkout path. IPC must target the same path used to launch Quickshell. Bindings are examples and may conflict with your existing shortcuts.

Default island interactions: left-click toggles the media player; horizontal dragging switches side views. The default secondary action is the legacy `toggleControlCenter`, which currently restores the resting view. Set it to `toggleOverview` or `toggleLyrics` for an alternative action.

### Glass and compositor styling

Dynis creates separate surfaces for compositor glass effects. The optical carrier namespaces are **`dynis-glass-island`** and **`dynis-glass-launcher`**; the interactive surfaces use **`dynis-capsule`** and **`dynis-launcher`**. Rounded corners use `dynis-corners`, and the workspace strip uses `dynis-left-island`.

Refraction needs a compatible compositor plugin configured for the carrier surfaces. Dynis does not install or configure that plugin. Without compositor effects, the intentionally near-transparent surfaces will not reproduce the screenshot backdrop. Avoid applying a second blur effect to a surface already managed by your glass plugin. Layer-rule syntax depends on your Hyprland version.

## Configuration

Dynis watches `$XDG_CONFIG_HOME/dynis/userconfig.json`, defaulting to `~/.config/dynis/userconfig.json`. After installation, use the interactive setup tool:

```bash
/usr/share/dynis/bin/dynis-setup --wizard
```

Or copy the [example configuration](config/userconfig.example.json) to that location if you do not already have a config. Keep the file valid JSON; changes are watched automatically.

| Option | Purpose |
| --- | --- |
| `wallpaperPath` | Wallpaper source for overview thumbnails |
| `textFontFamily`, `timeFontFamily`, `heroFontFamily` | Text fonts; default: Xanh Mono |
| `iconFontFamily` | Icon font; default: Symbols Nerd Font |
| `dynamicIslandPrimaryAction`, `dynamicIslandSecondaryAction` | Click actions, such as `toggleExpandedPlayer`, `toggleOverview`, `toggleLyrics`, or `showTime` |
| `dynamicIslandPrimaryButton`, `dynamicIslandSecondaryButton` | Mouse buttons; defaults: `1` and `3` |
| `dynamicIslandLeftSwipeItems` | Items in the custom side view; defaults: `cava`, `battery` |
| `disableAutoExpandOnTrackChange` | Keep the player from expanding automatically |
| `screenCornerRadius`, `screenEdgeShadowEnabled` | Screen-corner and edge styling |
| `workspaceOverviewWindowDragButton` | Button used to drag overview windows |

### Local data and lyrics

- User configuration can contain a TLP sudo password if you explicitly choose its `password` permission mode. Keep it private; the repository ignores local configuration files.
- Application ranking keeps a rolling seven-day usage history. **Currently it writes `launcher-usage.json` beside `shell.qml`**, not in the user config directory. It is ignored by Git; persistence may fail for a system installation where `/usr/share/dynis` is read-only to your user. Do not change system-directory permissions to work around this.
- Clipboard history is supplied by `cliphist`. Dynis does not start a clipboard-history watcher; configure one separately if you want history collection.
- The lyrics helper contacts external lyric providers using track metadata. Synced lyrics depend on provider availability and matching; `MUSIXMATCH_API_KEY` is optional and read from the environment. Do not put API keys in the repository.

## Troubleshooting

Inspect an installed service:

```bash
systemctl --user status dynis
journalctl --user -u dynis -b --no-pager -n 100
systemctl --user restart dynis
```

- **Backend import fails:** rebuild after Qt upgrades. For a checkout, use `run-local.sh` with the correct `BUILD_DIR`; for an installed copy, rebuild and reinstall.
- **Missing icons or unexpected typography:** install the bundled fonts and check your JSON font overrides. A personal configuration takes precedence over the defaults.
- **No notifications:** check for another notification daemon owning the D-Bus name. Test with `notify-send "Dynis" "Hello from the island"`.
- **Empty clipboard picker:** check that `cliphist list` has entries and that `wl-copy` is installed.
- **No lyrics in a local build:** set `QUICKSHELL_LYRICS_BACKEND` to the absolute path of the built `lyricsmpris` executable, as in the run example.
- **Service cannot reach the desktop:** check that the user service has the current Wayland and Hyprland session environment. Running `./run-local.sh` from a terminal inside the session helps separate service setup from shell errors.

## Development

The interface lives in `shell.qml`, the root window components, and [`qml/`](qml/). [`backend/`](backend/) contains the C++ Qt module; [`lyricsmpris/`](lyricsmpris/) contains the lyrics helper. [`tests/`](tests/) covers lyrics processing and user configuration, not full desktop interaction.

```bash
cmake --build build-release -j2
ctest --test-dir build-release --output-on-failure
git diff --check
```

Restart Quickshell after backend changes. For bug reports, include your Hyprland, Quickshell, and Qt versions, steps to reproduce, and relevant logs with personal data removed.

## Credits and license

Based on [enhaoswen/Tide-island](https://github.com/enhaoswen/Tide-island).

Dynis is distributed under the [GNU GPL v3.0](LICENSE). Bundled fonts retain their own licenses; see [`fonts/`](fonts/). Screenshot wallpaper is not included in the software distribution.
