#!/bin/bash
# Script to rename files with a specific extension to a prefix with sequential numbers

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Batch rename files with a given extension to PREFIX<N>.EXT

Options:
  -d DIR        Target directory (default: .)
  -e EXT        File extension to match, e.g. .txt (default: .txt)
  -p PREFIX     Prefix for renamed files (default: file)
  -s NUM        Starting sequence number (default: 1)
  -n            Dry-run / preview mode — show renames without executing
  -h            Show this help message

Examples:
  $(basename "$0")                          # default: ./*.txt -> file1.txt ...
  $(basename "$0") -d /tmp/docs -e .log -p log -s 10
  $(basename "$0") -n                       # preview only
EOF
  exit 0
}

# --- defaults ---------------------------------------------------------------
directory="."
prefix="file"
extension=".txt"
start=1
dry_run=0

# --- parse arguments --------------------------------------------------------
while getopts ":d:e:p:s:nh" opt; do
  case "$opt" in
    d) directory="$OPTARG" ;;
    e) extension="$OPTARG" ;;
    p) prefix="$OPTARG" ;;
    s) start="$OPTARG" ;;
    n) dry_run=1 ;;
    h) usage ;;
    :) echo "Error: -$OPTARG requires an argument." >&2; exit 1 ;;
    *) echo "Error: Unknown option -$OPTARG" >&2; usage ;;
  esac
done

# --- validate inputs --------------------------------------------------------
if [ ! -d "$directory" ]; then
  echo "Error: Directory '$directory' does not exist." >&2
  exit 1
fi

if [ -z "$extension" ]; then
  echo "Error: Extension must not be empty." >&2
  exit 1
fi

if ! [[ "$start" =~ ^[0-9]+$ ]]; then
  echo "Error: Starting number '$start' is not a valid non-negative integer." >&2
  exit 1
fi

# --- collect matching files -------------------------------------------------
shopt -s nullglob
files=("$directory"/*"$extension")
shopt -u nullglob

matched=${#files[@]}
if [ "$matched" -eq 0 ]; then
  echo "No files with extension '$extension' found in '$directory'."
  exit 0
fi

# --- pre-flight conflict check (scan ALL planned names before any rename) ---
count=$start
has_conflict=0
declare -a planned_sources
declare -a planned_targets

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  new_name="$directory/${prefix}${count}${extension}"
  planned_sources+=("$file")
  planned_targets+=("$new_name")
  # Conflict: target already exists AND is not the source itself
  if [ -e "$new_name" ] && [ "$(realpath "$file" 2>/dev/null)" != "$(realpath "$new_name" 2>/dev/null)" ]; then
    echo "Conflict: '$new_name' already exists (would collide with rename of '$file')." >&2
    has_conflict=1
  fi
  count=$((count + 1))
done

if [ "$has_conflict" -eq 1 ]; then
  echo "Error: One or more target filenames already exist. Aborting to avoid data loss." >&2
  exit 1
fi

# --- dry-run / preview mode -------------------------------------------------
if [ "$dry_run" -eq 1 ]; then
  echo "=== DRY-RUN preview (no files will be renamed) ==="
  for i in "${!planned_sources[@]}"; do
    echo "  ${planned_sources[$i]} -> ${planned_targets[$i]}"
  done
  echo "Total matched: ${#planned_sources[@]}"
  exit 0
fi

# --- execute renames --------------------------------------------------------
renamed=0
skipped=0
failed=0

for i in "${!planned_sources[@]}"; do
  src="${planned_sources[$i]}"
  dst="${planned_targets[$i]}"

  # Skip if source and target are the same file
  if [ "$(realpath "$src" 2>/dev/null)" = "$(realpath "$dst" 2>/dev/null)" ]; then
    echo "Skipped: '$src' is already named '$(basename "$dst")'"
    skipped=$((skipped + 1))
    continue
  fi

  if mv "$src" "$dst" 2>/dev/null; then
    echo "Renamed $src -> $dst"
    renamed=$((renamed + 1))
  else
    echo "Failed: could not rename '$src' -> '$dst'" >&2
    failed=$((failed + 1))
  fi
done

# --- summary ----------------------------------------------------------------
echo "---"
echo "Matched: ${#planned_sources[@]}  Renamed: $renamed  Skipped: $skipped  Failed: $failed"
