# Dynis

Dynis is a top-center Dynamic Island for **Hyprland**, built with **Quickshell**, QML, and Qt 6. It stays compact at rest and expands for notifications, media controls, quick settings, workspace overview, and system feedback.

Based on [enhaoswen/Tide-island](https://github.com/enhaoswen/Tide-island).

> This is an actively developed personal desktop-shell project. Expect occasional breaking changes and rough edges.

## Features

- Top-center clock and status capsule with animated transitions
- Freedesktop desktop notifications, including application icons and image previews
- Media controls, MPRIS metadata, optional synced lyrics, and CAVA visualizer
- Control center for volume, brightness, Wi-Fi, Bluetooth, battery, and power profiles
- Hyprland workspace indicator and overview
- Keyboard-driven application launcher and clipboard picker
- Fullscreen-aware visibility and rounded top screen corners
- Per-user JSON configuration in `~/.config/dynis/userconfig.json`

## Requirements

Required runtime dependencies:

- Hyprland and Quickshell
- Qt 6 with QML support
- `hyprctl`, `wpctl`, `pactl`, and `brightnessctl`
- UPower, BlueZ, and `libudev`

Optional integrations: NetworkManager or iwd (Wi-Fi), CAVA, an MPRIS-capable player, a Nerd Font, ImageMagick (wallpaper thumbnails), and TLP (power profiles).

For Debian/Ubuntu-like distributions, the included installer can install dependencies and build Quickshell:

```bash
./scripts/install-debian-ubuntu.sh
```

Pass `--help` to see its options. Review the script before running it: it uses `sudo` and installs system packages.

## Build and run

Install the bundled font set first. This makes the default configuration match the project appearance:

```bash
./scripts/install-fonts.sh
```

```bash
cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release -j"$(nproc)"
ctest --test-dir build-release --output-on-failure
```

To run the checkout without installing it:

```bash
BUILD_DIR="$PWD/build-release" ./run-local.sh
```

Useful IPC commands while running locally:

```bash
qs ipc -p "$PWD" call dynis togglePlayer
qs ipc -p "$PWD" call dynis showClock
qs ipc -p "$PWD" call overview toggle
```

## Install

```bash
cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build-release -j"$(nproc)"
sudo cmake --install build-release
systemctl --user daemon-reload
systemctl --user enable --now dynis
```

The installation also places Dynis fonts under `/usr/share/fonts/dynis`; the installed QML files live at `/usr/share/dynis`, and the user service is `dynis.service`.

To inspect or restart it:

```bash
systemctl --user status dynis
systemctl --user restart dynis
journalctl --user -u dynis -f
```

## Hyprland binds

Add bindings such as these to your Hyprland configuration after installing:

```conf
bind = $mainMod, M, exec, qs ipc -p /usr/share/dynis call dynis togglePlayer
bind = $mainMod, down, exec, qs ipc -p /usr/share/dynis call dynis showClock
bind = $mainMod, left, exec, qs ipc -p /usr/share/dynis call dynis showCustom
bind = $mainMod, right, exec, qs ipc -p /usr/share/dynis call dynis showLyrics
bind = $mainMod, TAB, exec, qs ipc -p /usr/share/dynis call overview toggle
bind = ALT, SPACE, exec, qs ipc -p /usr/share/dynis call dynis launcher
bind = $mainMod, V, exec, qs ipc -p /usr/share/dynis call dynis clipboard
```

For a local checkout, replace `/usr/share/dynis` with the absolute path to that checkout. The island and rounded-corner windows use the `dynis-capsule` and `dynis-corners` layer-shell namespaces; this rule is recommended:

```conf
layerrule = noanim, dynis-capsule
```

For compositor-level liquid glass, use a maintained Hyprland plugin with
layer-shell alpha-mask support, configured only for `dynis-capsule` and
`dynis-launcher`. Do not add `layerrule = blur` for those namespaces when the
glass plugin manages their backdrop.

## Launcher and clipboard

The application launcher is opened with `Alt+Space`; the clipboard picker is opened with `Super+V` in the example binds above. Both support typing to filter, `Up`/`Down` to change the selection, `Enter` to activate it, and `Esc` to close.

Application results learn from successful launches made through Dynis. The launcher stores a small rolling seven-day history in:

```text
~/.config/dynis/launcher-usage.json
```

With an empty query, recently and frequently used applications are shown first using a time-decayed score. While searching, match quality takes priority and usage only breaks ties. Mouse-wheel scrolling moves three rows per notch and synchronizes the keyboard selection with the centre of the visible list.

The clipboard picker requires `cliphist` and `wl-copy` (`wl-clipboard`).

## Configuration

Dynis reads and watches:

```text
~/.config/dynis/userconfig.json
```

Run `/usr/share/dynis/bin/dynis-setup --wizard` to create and edit it interactively. The default visual preset uses `Xanh Mono` for text and `Symbols Nerd Font` for icons; both are bundled with Dynis. Common options include `wallpaperPath`, font families, island click actions, `dynamicIslandLeftSwipeItems`, and `disableAutoExpandOnTrackChange`.

`tlpSudoPassword` may be stored in this file only when TLP's `password` mode is explicitly selected. Treat the file as private: do not commit or share it. `MUSIXMATCH_API_KEY`, if used for lyrics, is read from the environment rather than from the repository.

## Notifications

Dynis owns `org.freedesktop.Notifications`; do not run another notification daemon (such as dunst) alongside it. A quick smoke test:

```bash
notify-send "Dynis" "Hello from the island"
```

## Development

```bash
qmllint DynamicIslandWindow.qml qml/island/NotificationLayer.qml shell.qml
cmake --build build-release -j"$(nproc)"
ctest --test-dir build-release --output-on-failure
git diff --check
```

The QML interface lives in `shell.qml`, `DynamicIslandWindow.qml`, and `qml/`. The Qt backend module is in `backend/`; `lyricsmpris/` contains the lyrics helper and `tests/` contains its test coverage.

## License

Dynis is distributed under the [GNU GPL v3.0](LICENSE).

Bundled fonts retain their own licenses; see [`fonts/`](fonts/).
