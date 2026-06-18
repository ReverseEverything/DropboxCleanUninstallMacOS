# Dropbox Clean Uninstall for macOS

A dry-run-first cleanup script that removes Dropbox from macOS more completely than a regular app delete.

Made for [Reverse Everything](https://reverseeverything.com) by Ighor July.

GitHub repository [ReverseEverything/DropboxCleanUninstallMacOS](https://github.com/ReverseEverything/DropboxCleanUninstallMacOS).

## Why this exists

Dropbox can leave behind local state after uninstalling the app. That can include account data, updater files, launch items, File Provider registration data, local caches, temporary files, and user Library folders.

One practical case this helps with is Dropbox File Provider setup. If Dropbox was first configured with File Provider opted out, the app may not offer a clean way to turn File Provider back on. A complete local uninstall can reset the Dropbox state enough for the File Provider option to appear again during the next setup.

This script is designed for that kind of cleanup.

## What it removes

- Dropbox user data under `~/.dropbox`
- Dropbox Application Support data
- Dropbox updater files under the user Library
- Dropbox launch agents
- Dropbox File Provider state
- Dropbox app containers and group containers
- Dropbox preferences
- Dropbox caches, logs, HTTP storage, saved state, and temp files
- Optional synced local content under `~/Dropbox` and `~/Library/CloudStorage/Dropbox`
- Optional `/Applications/Dropbox.app`

## Safety defaults

The script is conservative by default.

- It runs as a dry run unless `--apply` is passed
- It keeps `/Applications/Dropbox.app` unless `--remove-app-bundle` is passed
- It does not use AppleScript unless `--use-osascript` is passed
- It stops before deletion if Dropbox processes are still running
- It only prunes empty Dropbox related folders

The script prints every command before running it.

## Usage

Review the dry run first.

```bash
bash uninstall-dropbox-complete.sh --user "$USER"
```

Run the cleanup.

```bash
sudo bash uninstall-dropbox-complete.sh --apply --user "$USER"
```

Remove the main app bundle too.

```bash
sudo bash uninstall-dropbox-complete.sh --apply --user "$USER" --remove-app-bundle
```

Keep local synced Dropbox files.

```bash
sudo bash uninstall-dropbox-complete.sh --apply --user "$USER" --keep-synced-content
```

Use AppleScript for quitting Dropbox and removing login items.

```bash
sudo bash uninstall-dropbox-complete.sh --apply --user "$USER" --use-osascript
```

Use all optional cleanup behavior.

```bash
sudo bash uninstall-dropbox-complete.sh --apply --user "$USER" --remove-app-bundle --use-osascript
```

## Options

`--apply`

Actually delete files. Without this flag, the script only prints what it would do.

`--user NAME`

Target a specific macOS user.

`--keep-synced-content`

Keep `~/Dropbox` and `~/Library/CloudStorage/Dropbox`.

`--remove-app-bundle`

Also remove `/Applications/Dropbox.app`.

`--use-osascript`

Use AppleScript to ask Dropbox to quit and remove login items. This can require additional macOS permissions, so it is off by default.

`--audit-list PATH`

Use a filesystem audit path list to remove extra Dropbox named leftovers discovered during an install snapshot.

`--remove-audit-side-effects`

Also remove safe Dropbox related side effects from the audit list.

## Process handling

Before deleting files in `--apply` mode, the script tries to stop Dropbox related launch items and processes. If anything Dropbox related is still running, it stops and prints the remaining processes.

Quit those processes in Activity Monitor, then press Return in the terminal to recheck.

## Notes

This script removes local Dropbox files and registrations. It does not delete any Dropbox account data from Dropbox servers.

Run it only after reviewing the dry run output.

## License

MIT
