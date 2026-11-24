# Open With Popup

A tiny macOS app that turns "Open With" into a popup. Make it the default app for
any file extensions you choose; opening one of those files (double-click, Return,
`open file.ext`) shows a menu at the mouse pointer with every app that can open it.

- Number keys 1–9 pick the first nine apps
- The app you last chose for an extension moves to the top
- Multi-file selections list only apps that can open all of them
- "Other…" picks any app; "Show in Finder" reveals the files

## Install

```bash
./build.sh
```

Builds `OpenWithPopup.app` and installs it to `~/Applications`.

## Settings

Open **Open With Popup** directly (Spotlight, `~/Applications`, or ⌘, while it's
running, or the last item in any popup) to add and remove extensions. Removing an
extension gives it back to the app that opened it before. macOS may ask you to
confirm each change of default app.

After first use the app keeps running in the background (no Dock icon), so the menu
appears instantly. Turn on **Start at login** in Settings to keep it ready after a
restart; quit it with ⌘Q while the Settings window is open.

## Command line

```bash
./owp --register md txt     # use the popup for these extensions
./owp --unregister md       # give .md back to its previous app
./owp --status              # managed extensions and whether each is active
./owp --list md             # apps that can open .md
./owp --restore md=com.microsoft.VSCode
```

## Signing and releases

`build.sh` signs with your **Developer ID Application** certificate if it's in the
keychain (or set `SIGN_ID`), with the hardened runtime. Without one it signs ad hoc,
which only runs on the Mac that built it.

To notarize and package a zip others can download, store notary credentials once:

```bash
xcrun notarytool store-credentials OpenWithPopup --apple-id you@example.com --team-id TEAMID
```

then:

```bash
NOTARIZE=1 ./build.sh
```

which writes `dist/OpenWithPopup.zip`.

## Icon

`swift tools/make_icon.swift` redraws `Resources/AppIcon.icns`.
