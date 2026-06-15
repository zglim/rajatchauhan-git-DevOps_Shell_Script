#!/bin/bash

# Backup script with rotation - keeps the latest 3 backups.
# Usage: backup_with_rotation.sh <directory_path>

set -euo pipefail

MAX_BACKUPS=3

# --- Parameter validation ---

if [ -z "${1:-}" ]; then
    echo "Error: No directory path provided." >&2
    echo "Usage: $0 <directory_path>" >&2
    exit 1
fi

DIR_PATH="$1"

if [ ! -e "$DIR_PATH" ]; then
    echo "Error: Path does not exist: $DIR_PATH" >&2
    exit 1
fi

if [ ! -d "$DIR_PATH" ]; then
    echo "Error: Not a directory: $DIR_PATH" >&2
    exit 1
fi

if [ ! -r "$DIR_PATH" ]; then
    echo "Error: Directory is not readable: $DIR_PATH" >&2
    exit 1
fi

# Use the real absolute path to avoid issues with relative paths and symlinks.
DIR_PATH="$(cd "$DIR_PATH" && pwd)"

# --- Create backup ---

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FOLDER="$DIR_PATH/backup_$TIMESTAMP"

if ! mkdir -p "$BACKUP_FOLDER"; then
    echo "Error: Failed to create backup directory: $BACKUP_FOLDER" >&2
    exit 1
fi

# Copy the contents of the source directory into the backup folder,
# excluding any backup_* directories to avoid recursive copying.
# We iterate over entries so we can skip backup_* dirs and handle
# the case where the directory has no regular files gracefully.
shopt -s dotglob nullglob
COPIED=0
for entry in "$DIR_PATH"/*; do
    base="$(basename "$entry")"

    # Skip any existing backup_* directories (including the one we just created)
    if [[ "$base" == backup_* ]] && [ -d "$entry" ]; then
        continue
    fi

    cp -a "$entry" "$BACKUP_FOLDER/"
    COPIED=$((COPIED + 1))
done
shopt -u dotglob nullglob

echo "Backup created: $BACKUP_FOLDER ($COPIED item(s) copied)"

# --- Rotation: keep only the latest MAX_BACKUPS backup directories ---

# Collect real backup directories (must be directories matching backup_*).
shopt -s nullglob
BACKUPS=()
for d in "$DIR_PATH"/backup_*; do
    [ -d "$d" ] && BACKUPS+=("$d")
done
shopt -u nullglob

# Sort by name (timestamps make lexicographic order == chronological order).
IFS=$'\n' SORTED=($(printf '%s\n' "${BACKUPS[@]}" | sort)); unset IFS

TOTAL=${#SORTED[@]}

if [ "$TOTAL" -gt "$MAX_BACKUPS" ]; then
    REMOVE_COUNT=$((TOTAL - MAX_BACKUPS))
    echo "Rotating: removing $REMOVE_COUNT old backup(s)..."
    for ((i = 0; i < REMOVE_COUNT; i++)); do
        echo "  Deleting: ${SORTED[$i]}"
        rm -rf "${SORTED[$i]}"
    done
fi

# Show the remaining backups
shopt -s nullglob
REMAINING=()
for d in "$DIR_PATH"/backup_*; do
    [ -d "$d" ] && REMAINING+=("$d")
done
shopt -u nullglob

IFS=$'\n' REMAINING_SORTED=($(printf '%s\n' "${REMAINING[@]}" | sort)); unset IFS

echo "Retained backups (${#REMAINING_SORTED[@]}):"
for d in "${REMAINING_SORTED[@]}"; do
    echo "  $d"
done
