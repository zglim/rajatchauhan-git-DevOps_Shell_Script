#!/bin/bash
# Script to rename files with a specific extension to a prefix with sequential numbers
# Supports CLI arguments, dry-run preview, conflict detection, and summary reporting.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
directory="."
prefix="file"
extension=".txt"
start_num=1
dry_run=false

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Batch-rename files that match a given extension to PREFIX<N><EXT>.

Options:
  -d, --directory DIR    Target directory (default: current directory)
  -e, --extension EXT    File extension to match, e.g. .txt (default: .txt)
  -p, --prefix PREFIX    Prefix for renamed files (default: file)
  -s, --start NUM        Starting sequence number (default: 1)
  -n, --dry-run          Preview renames without making changes
  -h, --help             Show this help message

Examples:
  $(basename "$0")                                  # defaults: .  file  .txt  1
  $(basename "$0") -d /tmp/photos -e .jpg -p img   # rename .jpg files in /tmp/photos
  $(basename "$0") -n -p backup -s 10              # dry-run with custom prefix & start
EOF
  exit 0
}

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--directory)  directory="$2";   shift 2 ;;
    -e|--extension)  extension="$2";   shift 2 ;;
    -p|--prefix)     prefix="$2";      shift 2 ;;
    -s|--start)      start_num="$2";   shift 2 ;;
    -n|--dry-run)    dry_run=true;     shift   ;;
    -h|--help)       usage                     ;;
    *)
      echo "Error: Unknown option '$1'. Use -h for help." >&2
      exit 1
      ;;
  esac
done

# ── Validate inputs ──────────────────────────────────────────────────────────

# 1. Directory must exist and be a directory
if [[ ! -d "$directory" ]]; then
  echo "Error: Directory '$directory' does not exist or is not a directory." >&2
  exit 1
fi

# 2. Extension must not be empty
if [[ -z "$extension" ]]; then
  echo "Error: Extension must not be empty." >&2
  exit 1
fi

# 3. Prefix must not be empty
if [[ -z "$prefix" ]]; then
  echo "Error: Prefix must not be empty." >&2
  exit 1
fi

# 4. Start number must be a positive integer
if ! [[ "$start_num" =~ ^[0-9]+$ ]] || [[ "$start_num" -le 0 ]]; then
  echo "Error: Start number must be a positive integer." >&2
  exit 1
fi

# ── Collect matching files ────────────────────────────────────────────────────
matched_files=()
while IFS= read -r -d '' f; do
  matched_files+=("$f")
done < <(find "$directory" -maxdepth 1 -type f -name "*${extension}" -print0 2>/dev/null | sort -z)

total_matched=${#matched_files[@]}

if [[ "$total_matched" -eq 0 ]]; then
  echo "No files with extension '$extension' found in '$directory'." >&2
  exit 1
fi

echo "Found $total_matched file(s) matching '*${extension}' in '$directory'."
if [[ "$dry_run" == true ]]; then
  echo "=== DRY-RUN MODE (no files will be changed) ==="
fi
echo ""

# ── Build rename plan ─────────────────────────────────────────────────────────
count="$start_num"
renamed=0
skipped=0
failed=0
declare -a skip_details=()
declare -a fail_details=()

for file in "${matched_files[@]}"; do
  base_dir="$(dirname "$file")"
  new_name="${prefix}${count}${extension}"
  new_path="${base_dir}/${new_name}"

  # Skip if the file is already named exactly what we would rename it to
  if [[ "$file" == "$new_path" ]]; then
    echo "  SKIP: '$file' is already named '$new_name'"
    skip_details+=("'$file' (already has target name)")
    skipped=$((skipped + 1))
    count=$((count + 1))
    continue
  fi

  # Conflict: target name already exists and is not the source file itself
  if [[ -e "$new_path" && "$file" != "$new_path" ]]; then
    echo "  CONFLICT: '$new_name' already exists — skipping." >&2
    skip_details+=("'$file' -> '$new_name' (target already exists)")
    skipped=$((skipped + 1))
    count=$((count + 1))
    continue
  fi

  if [[ "$dry_run" == true ]]; then
    echo "  PREVIEW: '$file' -> '$new_path'"
    renamed=$((renamed + 1))
  else
    if mv -- "$file" "$new_path" 2>/dev/null; then
      echo "  RENAMED: '$file' -> '$new_path'"
      renamed=$((renamed + 1))
    else
      echo "  FAILED: '$file' -> '$new_path'" >&2
      fail_details+=("'$file' -> '$new_path'")
      failed=$((failed + 1))
    fi
  fi

  count=$((count + 1))
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "───────────────────────────────────────"
echo "  Matched : $total_matched"
echo "  Renamed : $renamed"
echo "  Skipped : $skipped"
echo "  Failed  : $failed"
if [[ "$dry_run" == true ]]; then
  echo "  (dry-run — no changes were made)"
fi
echo "───────────────────────────────────────"

if [[ ${#skip_details[@]} -gt 0 ]]; then
  echo "Skipped files:"
  for s in "${skip_details[@]}"; do
    echo "  - $s"
  done
fi

if [[ ${#fail_details[@]} -gt 0 ]]; then
  echo "Failed renames:"
  for f in "${fail_details[@]}"; do
    echo "  - $f"
  done
fi

# Exit with non-zero if anything failed
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi

exit 0
