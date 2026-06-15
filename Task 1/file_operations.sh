#!/bin/bash

# file_operations.sh — Read a manifest file and report each listed file's size.

# --- Parameter validation ---
if [ $# -eq 0 ]; then
    echo "Usage: $0 <manifest_file>"
    echo "Error: No manifest file specified."
    exit 1
fi

filename="$1"

# Check if the manifest file exists
if [ ! -e "$filename" ]; then
    echo "Error: Manifest file '$filename' does not exist."
    exit 1
fi

# Check if the manifest file is readable
if [ ! -r "$filename" ]; then
    echo "Error: Manifest file '$filename' is not readable."
    exit 1
fi

# Resolve the directory that contains the manifest file, so that relative
# paths listed inside it are resolved relative to the manifest, not the
# caller's current working directory.
manifest_dir="$(cd "$(dirname "$filename")" && pwd)"

# Read each line from the manifest
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and whitespace-only lines
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # Skip comment lines (leading # with optional whitespace before it)
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Trim leading/trailing whitespace from the entry
    file="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # If the path is relative, resolve it against the manifest's directory
    if [[ "$file" != /* ]]; then
        file="${manifest_dir}/${file}"
    fi

    # Check if the file exists
    if [ ! -e "$file" ]; then
        echo "Error: File '$file' not found."
        continue
    fi

    # Check if the file is readable
    if [ ! -r "$file" ]; then
        echo "Error: File '$file' exists but is not readable."
        continue
    fi

    # Get file size portably (wc -c works on macOS, Linux, and BSDs)
    size=$(wc -c < "$file" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$size" ]; then
        echo "Error: Could not retrieve size for file '$file'."
        continue
    fi

    # Trim any leading whitespace that some wc implementations produce
    size=$(echo "$size" | tr -d '[:space:]')

    echo "File: $file, Size: $size bytes"
done < "$filename"
