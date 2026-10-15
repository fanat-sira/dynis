# Development and packaging

Build and test with the commands in the [README](../README.md). The backend uses GIO (`gio-unix-2.0`), Qt 6, and libudev. The CI workflow builds on Ubuntu 24.04 and runs Qt tests with `QT_QPA_PLATFORM=offscreen`; it does not validate a live Hyprland session.

## Tests

- Lyrics matching and normalization
- Typed configuration, invalid JSON, and removal of legacy stored passwords
- Desktop-entry visibility and user overrides, argument expansion, literal shell metacharacters, and launch failure
- TLP mode allowlist and polkit argument delegation without password input
- Launcher history persistence, merging writers, locking, malformed history, and file permissions
- Hyprland binding backup, idempotence, locking, and symlink preservation

Full desktop interaction, terminal-app behavior, live Bluetooth/Wi-Fi, and polkit prompts still need a graphical-session smoke test. Do not run the shell as root.

## Source releases

CMake and Arch packaging use the same version. Prepare a deterministic local source archive from the reviewed checkout:

```bash
python3 scripts/prepare-source.py
makepkg --verifysource
makepkg
```

Run this in the repository checkout (requires Python 3 and `makepkg`). The script creates `dynis-<version>.tar.gz` beside `PKGBUILD`, pins its SHA-256 in the recipe, and regenerates `.SRCINFO`. Source timestamps and ownership are normalized. Local settings, history, build directories, and agent state are excluded. Regenerate the archive after source changes.

For public distribution, publish the reviewed source commit first, then prepare packaging pinned to its full immutable commit ID:

```bash
python3 scripts/prepare-source.py --commit FULL_40_CHARACTER_COMMIT_ID
makepkg --verifysource
```

This downloads the GitHub archive, verifies its CMake version, and updates both packaging files with its immutable URL and checksum. It performs no commit, push, tag creation, or upload. Never substitute a branch archive or disable checksum verification.

The Debian/Ubuntu installer pins Quickshell v0.2.1 by full commit ID. An already installed Quickshell is kept unless `--force-build-quickshell` is selected. Updating that pin requires a compatibility check.
