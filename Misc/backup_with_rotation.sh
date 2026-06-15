#!/bin/bash

# Maximum number of backup directories to retain
MAX_BACKUPS=3

# --- Parameter validation ---
if [ -z "$1" ]; then
    echo "Usage: $0 <directory_path>"
    exit 1
fi

DIR_PATH="$1"

if [ ! -e "$DIR_PATH" ]; then
    echo "Error: '$DIR_PATH' does not exist."
    exit 1
fi

if [ ! -d "$DIR_PATH" ]; then
    echo "Error: '$DIR_PATH' is not a directory."
    exit 1
fi

if [ ! -r "$DIR_PATH" ]; then
    echo "Error: '$DIR_PATH' is not readable."
    exit 1
fi

# --- Create backup directory ---
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FOLDER="$DIR_PATH/backup_$TIMESTAMP"

if ! mkdir -p "$BACKUP_FOLDER"; then
    echo "Error: Failed to create backup directory '$BACKUP_FOLDER'."
    exit 1
fi

# --- Copy source contents, excluding backup_* directories ---
COPIED=0
shopt -s dotglob  # include hidden files
for item in "$DIR_PATH"/*; do
    # When the directory is empty, the glob literal is returned unexpanded
    [ -e "$item" ] || continue

    basename="$(basename "$item")"

    # Skip any existing backup_* directories to avoid recursive copy
    case "$basename" in
        backup_*) continue ;;
    esac

    if cp -r "$item" "$BACKUP_FOLDER/"; then
        COPIED=$((COPIED + 1))
    else
        echo "Warning: failed to copy '$item'."
    fi
done
shopt -u dotglob

echo "Backup created: $BACKUP_FOLDER  ($COPIED item(s) copied)"

# --- Rotation: keep only the newest MAX_BACKUPS backup directories ---
# Collect only directories directly under DIR_PATH whose names match backup_YYYY-MM-DD_HH-MM-SS
ALL_BACKUPS=()
while IFS= read -r line; do
    ALL_BACKUPS+=("$line")
done < <(find "$DIR_PATH" -maxdepth 1 -type d -name 'backup_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | sort)

TOTAL=${#ALL_BACKUPS[@]}

if [ "$TOTAL" -gt "$MAX_BACKUPS" ]; then
    REMOVE_COUNT=$((TOTAL - MAX_BACKUPS))
    echo "Rotating: removing $REMOVE_COUNT old backup(s)..."
    for (( i=0; i<REMOVE_COUNT; i++ )); do
        echo "  Removing: ${ALL_BACKUPS[$i]}"
        rm -rf "${ALL_BACKUPS[$i]}"
    done
fi

# --- Summary: list retained backups ---
KEPT_BACKUPS=()
while IFS= read -r line; do
    KEPT_BACKUPS+=("$line")
done < <(find "$DIR_PATH" -maxdepth 1 -type d -name 'backup_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | sort)

echo "Retained backups (${#KEPT_BACKUPS[@]}):"
for b in "${KEPT_BACKUPS[@]}"; do
    echo "  $b"
done
