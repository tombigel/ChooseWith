# Choose With

**Don't just open with. Choose with.**

The name is a twist on the Finder's **Open With** menu. Normally a file opens with
one fixed app; with Choose With, you choose what it opens with, every time.

Choose With is a small macOS app. Make it the default for the file extensions you
pick, and opening one of those files (double-click, ⌘↓, or `open file.ext`) shows a
menu at your pointer with every app that can open it.

## Using the menu

- **Return** opens the first app (it starts highlighted); **1–9** pick the first nine;
  **Esc** cancels.
- The app you chose last for an extension is listed first, unless you've set your
  own order for it.
- Apps you've hidden are one step away under **More Apps**.
- Select several files to open them together; only apps that can open all of them
  are listed.
- **Other…** picks any app; **Show in Finder** reveals the files.

## Install

```bash
./build.sh
```

Builds `ChooseWith.app` and installs it to `~/Applications`. Requires macOS 13 or
later.

## Settings

Open **Choose With** (Spotlight or `~/Applications`), press ⌘, while it's running,
or choose **Choose With Settings…** at the bottom of any menu.

**Extensions**
- Add extensions in the field at the bottom of the list (`md, txt, json`).
- The **pencil** next to an extension opens its app list: drag apps to reorder them
  (or right-click for Move to Top / Up / Down / Bottom), and untick the ones you
  don't need so they move under **More Apps**. **Show All**, **Hide All** and
  **Reset** are at the bottom.
- The **trash** removes an extension and gives it back to the app that opened it
  before.
- Apps, folders, disks, aliases and links can't be added, so opening them always
  works as usual.

**Behavior**
- **Start at login** keeps the menu instant after a restart. Choose With runs in
  the background without a Dock icon.
- **Take extensions back if another app claims them.** Apps can make themselves the
  default for a file type. With this off, Choose With warns you: the menu bar icon
  turns orange with a count, and Settings shows a banner with **Take Back**. With
  it on, Choose With switches them back automatically, posts a quiet notification,
  and notes it on the extension's row (it stops if an app re-claims the same
  extension 3 times in an hour).

**Appearance**
- Show or hide the menu bar icon, the splash screen, and Help when opening Choose
  With.

**Export / Import**
- **Export…** saves your extensions, app lists and settings to a JSON file you can
  keep with your dotfiles, put in iCloud Drive, or import on another Mac.
- **Import…** shows exactly what will change before applying anything. It replaces
  this Mac's setup with the file's.
- Per-Mac things aren't included: Start at login, which app each extension goes back
  to, and take-back history.
- An imported file is treated as untrusted: only regular files up to 1 MB are read,
  and every extension and app ID is validated. Nothing in it is ever run.

## Menu bar icon

Shows your active extensions (the full list in a submenu; click one to customize
it), and has Settings, How it works?, About, GitHub, Report a Bug, Start at Login,
Hide Menu Bar Icon and Quit. When another app has taken an extension, the icon turns
orange and the menu offers **Take Back**. When the icon is hidden, open the app
again to get back to Settings.

## Command line

Everything in Settings is also available from the terminal; a running copy of the
app picks up changes right away. `./choosewith --help` lists every option:

```bash
./choosewith --register md txt          # use the menu for these extensions
./choosewith --unregister md            # give .md back to its previous app
./choosewith --unregister-all           # give every extension back (before uninstalling)
./choosewith --status                   # extensions, their state, all settings

./choosewith --list svg                 # apps for .svg in menu order (hidden marked)
./choosewith --order svg Gapplin,Inkscape   # put these first (names or bundle IDs)
./choosewith --hide svg Safari "Google Chrome"   # move under "More Apps"
./choosewith --show svg Safari          # show again
./choosewith --reset svg                # default order, all shown

./choosewith --take-back on             # take extensions back automatically
./choosewith --take-back-now            # reclaim anything another app took

./choosewith --export settings.json     # save your setup (no file: print it)
./choosewith --import settings.json --dry-run   # show what would change
./choosewith --import settings.json     # apply it

./choosewith --login on                 # start at login
./choosewith --menubar off              # hide the menu bar icon
./choosewith --splash off               # no splash screen
./choosewith --help-on-launch off       # no Help window on open
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

which writes `dist/ChooseWith-<version>.zip` and prints its SHA-256. The version
comes from `CFBundleShortVersionString` in `Info.plist`.

## Icon

The app icon is an Icon Composer file, `Resources/AppIcon.icon` (open it in Icon
Composer to edit). `build.sh` compiles it with `actool`.

## License

MIT. See [LICENSE](LICENSE).

Found a bug? [Open an issue](https://github.com/tombigel/ChooseWith/issues/new).
