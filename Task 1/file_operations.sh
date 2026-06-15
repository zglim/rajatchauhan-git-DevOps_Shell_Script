#!/bin/bash

# ------------------------------------------------------------------
# file_operations.sh
# Reads a list file (one entry per line) and prints each file's size.
#
# - Paths in the list are resolved relative to the list file's own
#   directory, NOT the caller's current working directory.
# - Works on both GNU/Linux and macOS (no GNU-only stat flags).
# - Skips blank lines, whitespace-only lines, and comment lines (#).
# ------------------------------------------------------------------

# ---- Parameter validation ----------------------------------------

if [ $# -eq 0 ]; then
    echo "Usage: $0 <list_file>"
    echo "  list_file: a text file containing one filename per line"
    exit 1
fi

list_file="$1"

if [ ! -e "$list_file" ]; then
    echo "Error: List file '$list_file' does not exist."
    exit 1
fi

if [ ! -f "$list_file" ]; then
    echo "Error: '$list_file' is not a regular file."
    exit 1
fi

if [ ! -r "$list_file" ]; then
    echo "Error: List file '$list_file' is not readable."
    exit 1
fi

# ---- Resolve the list file's directory ---------------------------
# Relative paths inside the list are anchored to this directory.
list_dir="$(cd "$(dirname "$list_file")" && pwd)"

# ---- Portable file-size helper -----------------------------------
# Uses wc -c (POSIX) which works on both Linux and macOS.
get_file_size() {
    local target="$1"
    local size
    size=$(wc -c < "$target" 2>/dev/null) || return 1
    # Trim whitespace (macOS wc adds leading spaces)
    echo "${size// /}"
}

# ---- Main loop ---------------------------------------------------

while IFS= read -r line || [ -n "$line" ]; do

    # Strip leading whitespace for classification purposes
    trimmed="${line#"${line%%[![:space:]]*}"}"

    # Skip empty / whitespace-only lines
    if [ -z "$trimmed" ]; then
        continue
    fi

    # Skip comment lines (first non-whitespace character is #)
    if [[ "$trimmed" == \#* ]]; then
        continue
    fi

    # Use the original (untrimmed) line for display, but trim trailing
    # whitespace so it does not pollute path resolution.
    file="$line"
    # Strip trailing whitespace / carriage returns
    file="${file%"${file##*[![:space:]]}"}"

    # Resolve relative paths against the list file's directory
    if [[ "$file" != /* ]]; then
        file="${list_dir}/${file}"
    fi

    # Existence check
    if [ ! -e "$file" ]; then
        echo "Error: File not found: $line"
        continue
    fi

    # Readability check
    if [ ! -r "$file" ]; then
        echo "Error: File not readable: $line"
        continue
    fi

    # Retrieve size
    size=$(get_file_size "$file")
    if [ $? -ne 0 ] || [ -z "$size" ]; then
        echo "Error: Could not retrieve size for file: $line"
        continue
    fi

    echo "File: $line, Size: $size bytes"

done < "$list_file"
