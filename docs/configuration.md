# Configuration and desktop integration

Dynis watches `$XDG_CONFIG_HOME/dynis/userconfig.json`, defaulting to `~/.config/dynis/userconfig.json`. Start with [the example](../config/userconfig.example.json); keep the file valid JSON.

| Option | Purpose |
| --- | --- |
| `wallpaperPath` | Wallpaper source for overview thumbnails |
| `textFontFamily`, `timeFontFamily`, `heroFontFamily` | Text fonts; default: Xanh Mono |
| `iconFontFamily` | Icon font; default: Symbols Nerd Font |
| `dynamicIslandPrimaryAction`, `dynamicIslandSecondaryAction` | Click actions; defaults: `toggleExpandedPlayer`, `toggleOverview` |
| `dynamicIslandPrimaryButton`, `dynamicIslandSecondaryButton` | Mouse buttons; defaults: `1`, `3` |
| `dynamicIslandLeftSwipeItems` | Custom side-view items; defaults: `cava`, `battery` |
| `disableAutoExpandOnTrackChange` | Disable automatic player expansion |
| `screenCornerRadius`, `screenEdgeShadowEnabled` | Screen corners and edge styling |
| `workspaceOverviewWindowDragButton` | Button used to drag overview windows |
| `tlpPermissionMode` | `ask` uses polkit; `skip` disables TLP mode switching |

Other click actions include `toggleLyrics`, `showLyrics`, `showTime`, `openOverview`, and `closeOverview`.

## Glass surfaces

The optical carrier namespaces are `dynis-glass-island` and `dynis-glass-launcher`. Configure your compatible compositor glass plugin for those surfaces. Interactive surfaces use `dynis-capsule` and `dynis-launcher`; rounded corners use `dynis-corners`, and the workspace strip uses `dynis-left-island`.

Dynis does not install a compositor plugin. Avoid applying a second blur effect to a surface already managed by that plugin. Layer-rule syntax depends on your Hyprland version.

## IPC and keyboard controls

For an installed instance, use `qs ipc -p /usr/share/dynis call <target> <function>`. For local runs, pass the same absolute checkout path used to launch Quickshell.

| Target | Functions |
| --- | --- |
| `dynis` | `launcher`, `clipboard`, `closeLauncher`, `togglePlayer`, `showClock`, `showCustom`, `showLyrics`, `showWifi`, `showBluetooth`, `mainModDown`, `mainModUp` |
| `overview` | `toggle`, `open`, `close`, `refreshWallpaperCache` |

The launcher and clipboard support typing to filter, Up/Down to select, Enter to activate, and Esc to close. Applications are discovered and launched with [GIO desktop application APIs](https://docs.gtk.org/gio/iface.AppInfo.html), including XDG directory precedence, localized names, desktop visibility rules, and desktop-entry argument expansion.

## Local data and permissions

Application ranking uses a seven-day history in `$XDG_STATE_HOME/dynis/launcher-usage.json` (default: `~/.local/state/dynis/launcher-usage.json`). A backend singleton shares it between monitors; writes are atomic, private to the user, and locked across processes. The old checkout-local history is no longer read or updated. Invalid history is left unchanged and reported in the shell log.

Dynis never collects or stores an administrative password. TLP operations use `pkexec` with a fixed executable and an allowed mode, authorized by polkit. Install a session authentication agent to receive authorization prompts. No broad passwordless rule is installed. Old `tlpSudoPassword` fields are removed atomically from Dynis and legacy Tide Island configs; `password` mode becomes `ask`. A failed cleanup is reported rather than enabling password-based authorization.

The setup wizard backs up an existing Hyprland config before editing it, preserves symlinks, and avoids duplicate overview bindings. It does not edit system files.

The clipboard picker uses `cliphist` and `wl-copy`; configure a clipboard-history watcher separately. Lyrics use external providers; an optional `MUSIXMATCH_API_KEY` comes from the environment.

## Service and troubleshooting

Choose one startup method: the `dynis` user service, or `exec-once = dynis` in Hyprland.

```bash
systemctl --user status dynis
journalctl --user -u dynis -b --no-pager -n 100
systemctl --user restart dynis
```

After a package upgrade, restart Dynis from your graphical session. Package hooks print instructions and do not invoke user services as root.

- Backend import errors: rebuild after Qt upgrades; use the correct `BUILD_DIR` for local runs.
- Unexpected fonts: install bundled fonts and check JSON font overrides.
- Missing notifications: check for another notification daemon; test with `notify-send "Dynis" "Hello from the island"`.
- Empty clipboard: check `cliphist list` and the availability of `wl-copy`.
- Missing local-build lyrics: set `QUICKSHELL_LYRICS_BACKEND` to the built helper's absolute path.
- Service cannot reach the desktop: check its Wayland and Hyprland session environment; compare with a local run from a desktop terminal.
