#!/usr/bin/env bash
#
# cleanup.sh — Deep-clean a cloud VM, leaving only a minimal Ubuntu install.
#
# Usage: sudo ./cleanup.sh [ -n | --dry-run ] [ -y | --yes ] [ -h | --help ]
#  -n, --dry-run   Show what would be done, but don’t actually remove anything
#  -y, --yes       Skip confirmation prompt
#  -h, --help      Display this help and exit
#

set -euo pipefail
DRY_RUN=0
AUTO_YES=0

# trap Ctrl-C
trap 'echo -e "\nInterrupted. Exiting."; exit 1' INT

usage() {
  cat <<EOF
Usage: sudo $0 [OPTIONS]

Options:
  -n, --dry-run    Show actions without making changes
  -y, --yes        Skip confirmation prompt
  -h, --help       Show this help message

Example:
  sudo $0          # run interactively
  sudo $0 -n       # dry-run
  sudo $0 -y       # auto-yes
EOF
  exit 0
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)  DRY_RUN=1; shift ;;
    -y|--yes)      AUTO_YES=1; shift ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# helper to run or echo
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] $*"
  else
    echo "→ $*"
    eval "$@"
  fi
}

# confirmation
if [[ $AUTO_YES -eq 0 ]]; then
  cat <<EOF
*** WARNING ***
This will PERMANENTLY delete:
  • all non-root users and their home directories  
  • all manually installed packages (leaving only ubuntu-minimal/standard)  
  • all logs, caches, temp files under /var, /home, /tmp, /root (except SSH keys)  
Are you sure you want to proceed? (yes/no)
EOF
  read -r REPLY
  if [[ "$REPLY" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Starting cleanup at $(date)."

# 1. Protect base packages
run "apt-mark manual ubuntu-minimal ubuntu-standard \$(apt-cache depends ubuntu-standard | awk '/Depends:/ {print \$2}') >/dev/null"

# 2. Mark others auto-removable
run "apt-mark auto \$(apt-mark showmanual) >/dev/null || true"

# 3. Purge all auto packages
echo "Purging auto-installed packages..."
AUTO_PKGS=$(apt-mark showauto)
if [[ -n "$AUTO_PKGS" ]]; then
  run "apt-get -y purge $AUTO_PKGS"
else
  echo "Nothing to purge."
fi

# 4. Autoremove, clean apt
echo "Cleaning up APT..."
run "apt-get -y autoremove --purge"
run "apt-get clean"

# 5. Remove non-root users
echo "Deleting non-root users..."
for user in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
  run "userdel -r $user || true"
done

# 6. Wipe data, logs, temp
echo "Removing files and logs..."
run "rm -rf /home/* /var/tmp/* /tmp/*"
run "find /root -mindepth 1 ! -path '/root/.ssh*' -delete"
run "rm -rf /var/log/*"

# 7. Vacuum journal
echo "Clearing journal logs..."
run "journalctl --rotate"
run "journalctl --vacuum-time=1s"

echo "Cleanup complete at $(date)."
if [[ $DRY_RUN -eq 0 ]]; then
  echo "Please reboot the VM now: sudo reboot"
else
  echo "[DRY-RUN] Skipped actual cleanup."
fi
