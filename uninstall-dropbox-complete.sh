#!/usr/bin/env bash
#
# Dropbox uninstall cleanup for macOS
# Made by Ighor July for https://reverseeverything.com
# GitHub repository https://github.com/ReverseEverything/DropboxCleanUninstallMacOS
#
# Dry run is the default. Pass --apply to delete files.
# /Applications/Dropbox.app is kept by default.
# Pass --remove-app-bundle to remove the main app bundle.
# AppleScript is disabled by default.
# Pass --use-osascript to allow AppleScript based quit and login item cleanup.

set -u
set -o pipefail

apply=0
target_user=""
target_home=""
keep_synced_content=0
remove_app_bundle=0
use_osascript=0
remove_audit_side_effects=0
audit_list=""

usage() {
  cat <<'EOF'
Usage
  sudo bash uninstall-dropbox-complete.sh --apply --user admin

Dry run
  bash uninstall-dropbox-complete.sh --user admin

Options
  --apply
      Delete files. Without this flag the script only prints actions.

  --user NAME
      Remove Dropbox data for this macOS user.

  --keep-synced-content
      Keep ~/Dropbox and ~/Library/CloudStorage/Dropbox.

  --remove-app-bundle
      Also remove /Applications/Dropbox.app.
      The app bundle is kept by default.

  --use-osascript
      Use AppleScript to ask Dropbox to quit and to remove login items.
      This is disabled by default because macOS may require extra permissions.

  --audit-list PATH
      Optional path list from the filesystem audit.
      Only Dropbox named paths from this list are removed.

  --remove-audit-side-effects
      Also remove safe Dropbox related side effects from the audit list.
      This does not delete Apple system asset stores or shared databases.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --apply)
    apply=1
    ;;
  --user)
    shift
    if [ "$#" -eq 0 ]; then
      echo "Missing value for --user" >&2
      exit 2
    fi
    target_user="$1"
    ;;
  --keep-synced-content)
    keep_synced_content=1
    ;;
  --remove-app-bundle)
    remove_app_bundle=1
    ;;
  --use-osascript)
    use_osascript=1
    ;;
  --audit-list)
    shift
    if [ "$#" -eq 0 ]; then
      echo "Missing value for --audit-list" >&2
      exit 2
    fi
    audit_list="$1"
    ;;
  --remove-audit-side-effects)
    remove_audit_side_effects=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option $1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
if [ -z "$audit_list" ] && [ -f "$script_dir/dropbox-added-normalized-paths-without-audit.txt" ]; then
  audit_list="$script_dir/dropbox-added-normalized-paths-without-audit.txt"
fi

detect_user() {
  if [ -n "$target_user" ]; then
    return
  fi

  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    target_user="$SUDO_USER"
    return
  fi

  local console_user
  console_user="$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"
  if [ -n "$console_user" ] && [ "$console_user" != "root" ]; then
    target_user="$console_user"
    return
  fi

  target_user="${USER:-}"
}

detect_home() {
  target_home="$(/usr/bin/dscl . -read "/Users/$target_user" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}' || true)"
  if [ -z "$target_home" ]; then
    target_home="/Users/$target_user"
  fi
}

detect_user
if [ -z "$target_user" ]; then
  echo "Could not determine target user. Pass --user NAME" >&2
  exit 2
fi

detect_home
if [ ! -d "$target_home" ]; then
  echo "Target home does not exist. $target_home" >&2
  exit 2
fi

target_uid="$(/usr/bin/id -u "$target_user" 2>/dev/null || true)"
if [ -z "$target_uid" ]; then
  echo "Could not determine uid for $target_user" >&2
  exit 2
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo for full removal. Dry run still works without sudo." >&2
fi

if [ "$apply" -eq 0 ]; then
  echo "Dry run mode. Re-run with --apply to delete."
fi

echo "Target user $target_user"
echo "Target home $target_home"

print_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run_cmd() {
  print_cmd "$@"
  if [ "$apply" -eq 1 ]; then
    "$@"
  fi
}

try_cmd() {
  print_cmd "$@"
  if [ "$apply" -eq 1 ]; then
    "$@" || true
  fi
}

run_as_user() {
  if [ "$(id -u)" -eq 0 ]; then
    try_cmd /bin/launchctl asuser "$target_uid" /usr/bin/sudo -u "$target_user" "$@"
  else
    try_cmd "$@"
  fi
}

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

remove_path() {
  local path="$1"

  case "$path" in
  "" | "/" | "/Applications" | "/Library" | "/System" | "/Users" | "/private" | "/private/var" | "/private/var/folders" | "$target_home" | "$target_home/Library")
    echo "Skip unsafe path $path" >&2
    return
    ;;
  esac

  if path_exists "$path"; then
    run_cmd /bin/rm -rf "$path"
  fi
}

rmdir_empty() {
  local path="$1"
  case "$path" in
  "" | "/" | "/Applications" | "/Library" | "/System" | "/Users" | "/private" | "/private/var" | "$target_home" | "$target_home/Library")
    return
    ;;
  esac

  if [ -d "$path" ]; then
    try_cmd /bin/rmdir "$path"
  fi
}

remove_glob() {
  local path
  for path in "$@"; do
    remove_path "$path"
  done
}

unload_launch_items() {
  local item

  for item in \
    "$target_home/Library/LaunchAgents/com.dropbox.DropboxUpdater.wake.plist" \
    "$target_home/Library/LaunchAgents/com.dropbox.dropboxmacupdate.agent.plist" \
    "$target_home/Library/LaunchAgents/com.dropbox.dropboxmacupdate.xpcservice.plist"; do
    if path_exists "$item"; then
      try_cmd /bin/launchctl bootout "gui/$target_uid" "$item"
    fi
  done

  for item in \
    /Library/LaunchDaemons/com.dropbox.DropboxMacUpdate.agent.plist \
    /Library/LaunchDaemons/com.dropbox.dropboxmacupdate.agent.plist \
    /Library/LaunchDaemons/com.getdropbox.dropbox.UpdaterPrivilegedHelper.plist; do
    if path_exists "$item"; then
      try_cmd /bin/launchctl bootout system "$item"
    fi
  done
}

stop_dropbox() {
  if [ "$use_osascript" -eq 1 ]; then
    run_as_user /usr/bin/osascript -e 'tell application "Dropbox" to quit'
  else
    echo "Skipping AppleScript quit command. Pass --use-osascript to enable it."
  fi

  /bin/sleep 2

  try_cmd /usr/bin/pkill -x Dropbox
  try_cmd /usr/bin/pkill -f 'Dropbox Helper'
  try_cmd /usr/bin/pkill -f DropboxMacUpdate
  try_cmd /usr/bin/pkill -f DropboxUpdateClient
  try_cmd /usr/bin/pkill -f DropboxSoftwareUpdate
  try_cmd /usr/bin/pkill -f com.getdropbox.dropbox
  try_cmd /usr/bin/pkill -f com.dropbox
}

list_dropbox_processes() {
  {
    /usr/bin/pgrep -fl 'Dropbox' 2>/dev/null || true
    /usr/bin/pgrep -fl 'Dropbox Helper' 2>/dev/null || true
    /usr/bin/pgrep -fl 'DropboxMacUpdate' 2>/dev/null || true
    /usr/bin/pgrep -fl 'DropboxUpdateClient' 2>/dev/null || true
    /usr/bin/pgrep -fl 'DropboxSoftwareUpdate' 2>/dev/null || true
    /usr/bin/pgrep -fl 'com.getdropbox.dropbox' 2>/dev/null || true
    /usr/bin/pgrep -fl 'com.dropbox.' 2>/dev/null || true
    /usr/bin/pgrep -fl 'G7HH3F8CAK.com.getdropbox.dropbox.sync' 2>/dev/null || true
  } | /usr/bin/sort -u | /usr/bin/awk '
    $0 ~ /uninstall-dropbox-complete[.]sh/ { next }
    $0 ~ /[p]grep -fl/ { next }
    $0 ~ /[a]wk / { next }
    { print }
  '
}

ensure_no_dropbox_processes() {
  if [ "$apply" -eq 0 ]; then
    echo "Skipping live process guard in dry run mode."
    return
  fi

  local running
  local reply

  while true; do
    running="$(list_dropbox_processes || true)"
    if [ -z "$running" ]; then
      return
    fi

    echo "Dropbox related processes are still running."
    echo "$running"
    echo "Quit these processes in Activity Monitor, then press Return to check again."
    echo "Type q and press Return to abort."

    if [ ! -t 0 ]; then
      echo "Cannot continue in a non interactive shell while Dropbox processes are running." >&2
      exit 1
    fi

    read -r reply
    case "$reply" in
    q | Q | quit | QUIT)
      echo "Aborted because Dropbox processes are still running." >&2
      exit 1
      ;;
    esac
  done
}

reset_shared_registrations() {
  local bundle

  for bundle in \
    com.getdropbox.dropbox \
    com.getdropbox.dropbox.fileprovider \
    com.getdropbox.dropbox.TransferExtension \
    com.getdropbox.dropbox.garcon \
    com.dropbox.client.crashpad \
    G7HH3F8CAK.com.getdropbox.dropbox.sync; do
    if command -v tccutil >/dev/null 2>&1; then
      run_as_user /usr/bin/tccutil reset All "$bundle"
      if [ "$(id -u)" -eq 0 ]; then
        try_cmd /usr/bin/tccutil reset All "$bundle"
      fi
    fi

    if command -v pluginkit >/dev/null 2>&1; then
      run_as_user /usr/bin/pluginkit -r -i "$bundle"
      if [ "$(id -u)" -eq 0 ]; then
        try_cmd /usr/bin/pluginkit -r -i "$bundle"
      fi
    fi
  done

  if [ "$use_osascript" -eq 1 ]; then
    run_as_user /usr/bin/osascript -e 'tell application "System Events" to delete every login item whose name contains "Dropbox"'
  else
    echo "Skipping AppleScript login item cleanup. Pass --use-osascript to enable it."
  fi
}

remove_core_paths() {
  if [ "$remove_app_bundle" -eq 1 ]; then
    remove_path /Applications/Dropbox.app
  else
    echo "Keeping /Applications/Dropbox.app. Pass --remove-app-bundle to delete it."
  fi

  if [ "$keep_synced_content" -eq 0 ]; then
    remove_path "$target_home/Dropbox"
    remove_path "$target_home/Library/CloudStorage/Dropbox"
  fi

  remove_path "$target_home/.dropbox"
  remove_path "$target_home/.dropbox-master"
  remove_path "$target_home/.dropbox-dist"

  remove_path "$target_home/Library/Application Support/Dropbox"
  remove_path "$target_home/Library/Dropbox"
  remove_path "$target_home/Library/Application Support/FileProvider/com.getdropbox.dropbox.fileprovider"

  remove_path "$target_home/Library/Containers/com.getdropbox.dropbox.TransferExtension"
  remove_path "$target_home/Library/Containers/com.getdropbox.dropbox.fileprovider"
  remove_path "$target_home/Library/Containers/com.getdropbox.dropbox.garcon"

  remove_path "$target_home/Library/Group Containers/G7HH3F8CAK.com.getdropbox.dropbox.sync"
  remove_path "$target_home/Library/Group Containers/com.dropbox.client.crashpad"

  remove_path "$target_home/Library/Application Scripts/G7HH3F8CAK.com.getdropbox.dropbox.sync"
  remove_path "$target_home/Library/Application Scripts/com.dropbox.client.crashpad"
  remove_path "$target_home/Library/Application Scripts/com.getdropbox.dropbox.TransferExtension"
  remove_path "$target_home/Library/Application Scripts/com.getdropbox.dropbox.fileprovider"
  remove_path "$target_home/Library/Application Scripts/com.getdropbox.dropbox.garcon"

  remove_path "$target_home/Library/LaunchAgents/com.dropbox.DropboxUpdater.wake.plist"
  remove_path "$target_home/Library/LaunchAgents/com.dropbox.dropboxmacupdate.agent.plist"
  remove_path "$target_home/Library/LaunchAgents/com.dropbox.dropboxmacupdate.xpcservice.plist"

  remove_path "$target_home/Library/Preferences/com.dropbox.DropboxMacUpdate.plist"
  remove_path "$target_home/Library/Preferences/com.getdropbox.dropbox.plist"

  remove_path "$target_home/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.getdropbox.dropbox.sfl4"

  remove_path /Library/PrivilegedHelperTools/com.getdropbox.dropbox.UpdaterPrivilegedHelper
  remove_path /Library/LaunchDaemons/com.dropbox.DropboxMacUpdate.agent.plist
  remove_path /Library/LaunchDaemons/com.dropbox.dropboxmacupdate.agent.plist
  remove_path /Library/LaunchDaemons/com.getdropbox.dropbox.UpdaterPrivilegedHelper.plist

  remove_glob /private/var/db/receipts/com.dropbox.* /private/var/db/receipts/com.getdropbox.*
}

remove_caches_and_temp() {
  remove_glob \
    "$target_home/Library/Caches/com.dropbox"* \
    "$target_home/Library/Caches/com.getdropbox"* \
    "$target_home/Library/Caches/Dropbox"* \
    "$target_home/Library/Caches/"*Dropbox* \
    "$target_home/Library/HTTPStorages/com.dropbox"* \
    "$target_home/Library/HTTPStorages/com.getdropbox"* \
    "$target_home/Library/WebKit/com.dropbox"* \
    "$target_home/Library/WebKit/com.getdropbox"* \
    "$target_home/Library/Cookies/com.dropbox"* \
    "$target_home/Library/Cookies/com.getdropbox"* \
    "$target_home/Library/Logs/Dropbox"* \
    "$target_home/Library/Logs/com.dropbox"* \
    "$target_home/Library/Logs/com.getdropbox"* \
    "$target_home/Library/Saved Application State/com.dropbox"* \
    "$target_home/Library/Saved Application State/com.getdropbox"*

  remove_glob \
    /private/var/folders/*/*/*/com.dropbox* \
    /private/var/folders/*/*/*/com.getdropbox* \
    /private/tmp/com.dropbox* \
    /private/tmp/com.getdropbox* \
    /tmp/com.dropbox* \
    /tmp/com.getdropbox* \
    /var/tmp/com.dropbox* \
    /var/tmp/com.getdropbox*
}

audit_path_is_dropbox_owned() {
  local path="$1"

  case "$path" in
  *Dropbox* | *dropbox* | *getdropbox* | *G7HH3F8CAK.com.getdropbox.dropbox.sync*)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

audit_path_is_safe_side_effect() {
  local path="$1"

  case "$path" in
  "$target_home/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.getdropbox.dropbox.sfl4")
    return 0
    ;;
  /Applications/.DS_Store)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

remove_from_audit_list() {
  if [ -z "$audit_list" ] || [ ! -f "$audit_list" ]; then
    return
  fi

  echo "Using audit list $audit_list"

  local reversed_list
  reversed_list="$(/usr/bin/mktemp "/tmp/dropbox-uninstall-audit.XXXXXX")"
  /usr/bin/tail -r "$audit_list" >"$reversed_list"

  local path
  while IFS= read -r path; do
    path="${path/#\/Users\/admin/$target_home}"

    if audit_path_is_dropbox_owned "$path"; then
      if [ "$remove_app_bundle" -eq 0 ]; then
        case "$path" in
        /Applications/Dropbox.app | /Applications/Dropbox.app/* | /System/Volumes/Data/Applications/Dropbox.app | /System/Volumes/Data/Applications/Dropbox.app/*)
          continue
          ;;
        esac
      fi

      if [ "$keep_synced_content" -eq 1 ]; then
        case "$path" in
        "$target_home/Dropbox" | "$target_home/Dropbox/"* | "$target_home/Library/CloudStorage/Dropbox" | "$target_home/Library/CloudStorage/Dropbox/"*)
          continue
          ;;
        esac
      fi
      remove_path "$path"
      continue
    fi

    if [ "$remove_audit_side_effects" -eq 1 ] && audit_path_is_safe_side_effect "$path"; then
      remove_path "$path"
    fi
  done <"$reversed_list"

  /bin/rm -f "$reversed_list"
}

prune_empty_dirs() {
  if [ "$keep_synced_content" -eq 0 ]; then
    rmdir_empty "$target_home/Library/CloudStorage/Dropbox"
  fi

  rmdir_empty "$target_home/.dropbox"
  rmdir_empty "$target_home/Library/Application Support/Dropbox"
  rmdir_empty "$target_home/Library/Dropbox"
  rmdir_empty "$target_home/Library/Application Support/FileProvider/com.getdropbox.dropbox.fileprovider"

  rmdir_empty "$target_home/Library/Application Scripts/G7HH3F8CAK.com.getdropbox.dropbox.sync"
  rmdir_empty "$target_home/Library/Application Scripts/com.dropbox.client.crashpad"
  rmdir_empty "$target_home/Library/Application Scripts/com.getdropbox.dropbox.TransferExtension"
  rmdir_empty "$target_home/Library/Application Scripts/com.getdropbox.dropbox.fileprovider"
  rmdir_empty "$target_home/Library/Application Scripts/com.getdropbox.dropbox.garcon"

  rmdir_empty "$target_home/Library/Group Containers/G7HH3F8CAK.com.getdropbox.dropbox.sync"
  rmdir_empty "$target_home/Library/Group Containers/com.dropbox.client.crashpad"

  rmdir_empty "$target_home/Library/Containers/com.getdropbox.dropbox.TransferExtension"
  rmdir_empty "$target_home/Library/Containers/com.getdropbox.dropbox.fileprovider"
  rmdir_empty "$target_home/Library/Containers/com.getdropbox.dropbox.garcon"
}

shopt -s nullglob

unload_launch_items
stop_dropbox
ensure_no_dropbox_processes
reset_shared_registrations
remove_core_paths
remove_caches_and_temp
remove_from_audit_list
prune_empty_dirs

echo "Dropbox uninstall cleanup finished"
if [ "$apply" -eq 0 ]; then
  echo "Dry run only. No files were deleted."
fi
