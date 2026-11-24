# Choose With

**Don't just open with. Choose with.**

The name is a twist on the Finder's **Open With**.

A tiny macOS app that turns "Open With" into a popup. Make it the default app for
any file extensions you choose; opening one of those files (double-click, Return,
`open file.ext`) shows a menu at the mouse pointer with every app that can open it.

- Return picks the first app; number keys 1–9 pick the first nine
- The app you last chose for an extension moves to the top
- Multi-file selections list only apps that can open all of them
- "Other…" picks any app; "Show in Finder" reveals the files

## Install

```bash
./build.sh
```

Builds `ChooseWith.app` and installs it to `~/Applications`.

## Settings

Open **Choose With** directly (Spotlight, `~/Applications`, or ⌘, while it's
running, or the last item in any popup) to add and remove extensions. Removing an
extension gives it back to the app that opened it before. Apps, folders, disks,
aliases and links can't be added, so opening them always works as usual. macOS may ask you to
confirm each change of default app.

After first use the app keeps running in the background (no Dock icon), so the menu
appears instantly. Turn on **Start at login** in Settings to keep it ready after a
restart.

A **menu bar icon** shows which extensions are active and has Settings, Start at
Login, Hide Menu Bar Icon and Quit. Hide or show it from the menu or in Settings;
when it's hidden, open the app again to get back to Settings.

**Help** (Help menu, ⌘?, "How It Works…" in the menu bar menu, or the **?** button in
Settings) explains how it works; it also opens on first launch. Opening the app
directly shows a short splash screen; starting at login or opening a file never does.

## Command line

```bash
./choosewith --register md txt     # use the popup for these extensions
./choosewith --unregister md       # give .md back to its previous app
./choosewith --login on            # start at login (or off)
./choosewith --status              # managed extensions and whether each is active
./choosewith --list md             # apps that can open .md
./choosewith --restore md=com.microsoft.VSCode
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

which writes `dist/ChooseWith.zip`.

## Icon

`swift tools/make_icon.swift` redraws `Resources/AppIcon.icns`.

## License

MIT. See [LICENSE](LICENSE).

Found a bug? [Open an issue](https://github.com/tombigel/ChooseWith/issues/new).
