# Changelog

All notable changes to Choose With. Versions follow [Semantic Versioning](https://semver.org).

## Unreleased

- Exported settings files are named with the Mac's name and the date, and record
  where, when and from which version they were exported. Import shows that before
  applying. `--export` to a folder uses the same name.

## 1.0.0 — 2026-11-25

First release.

- Menu at the pointer with app icons when you open a file of a chosen extension;
  Return opens the first app, 1–9 pick others, Esc cancels
- Multi-file selections list only apps that can open all of them; Other… and
  Show in Finder
- Per-extension app lists: reorder (drag, or right-click Move) and hide apps, which
  move under More Apps
- Settings in a System Settings–style form; Help and a splash screen, each optional
- Menu bar icon with your extensions, Settings, Help, About, GitHub and Report a Bug
- Takeover warnings: an orange menu bar icon and a Settings banner when another app
  claims one of your extensions, with optional automatic take-back and notifications
- Start at login; runs in the background without a Dock icon
- Export / Import settings as JSON, validated as untrusted input
- Full command line: `--help` lists every option
- Apps, folders, disks, aliases and links can't be added
- Signed with a Developer ID and notarized; universal; macOS 13 or later
