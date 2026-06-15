#!/bin/bash

# Log analysis tool - analyzes log files and generates summary reports
# Supports custom keywords, top-N, output/archive directories, and multiple log files.

set -euo pipefail

# Defaults
error_keyword="ERROR"
critical_keyword="CRITICAL"
top_n=5
output_dir="."
archive_dir="processed_logs"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] <logfile> [logfile ...]

Analyze log files and generate summary reports.

Options:
  -e KEYWORD   Error keyword to search for (default: ERROR)
  -c KEYWORD   Critical keyword to search for (default: CRITICAL)
  -n NUM       Number of top error messages to show (default: 5)
  -o DIR       Output directory for summary reports (default: current directory)
  -a DIR       Archive directory for processed logs (default: processed_logs)
  -h           Show this help message

Examples:
  $0 /var/log/app.log
  $0 -e WARN -c FATAL -n 10 -o reports/ app1.log app2.log
EOF
    exit "${1:-1}"
}

# Parse options
while getopts ":e:c:n:o:a:h" opt; do
    case "$opt" in
        e) error_keyword="$OPTARG" ;;
        c) critical_keyword="$OPTARG" ;;
        n) top_n="$OPTARG" ;;
        o) output_dir="$OPTARG" ;;
        a) archive_dir="$OPTARG" ;;
        h) usage 0 ;;
        :) echo "Error: Option -$OPTARG requires an argument." >&2; exit 1 ;;
        *) echo "Error: Unknown option -$OPTARG." >&2; usage 1 ;;
    esac
done
shift $((OPTIND - 1))

# Validate: at least one log file required
if [ $# -eq 0 ]; then
    echo "Error: No log file specified." >&2
    usage 1
fi

# Validate: keywords must not be empty
if [ -z "$error_keyword" ]; then
    echo "Error: Error keyword (-e) must not be empty." >&2
    exit 1
fi
if [ -z "$critical_keyword" ]; then
    echo "Error: Critical keyword (-c) must not be empty." >&2
    exit 1
fi

# Validate: top_n must be a positive integer
if ! [[ "$top_n" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Top N (-n) must be a positive integer, got '$top_n'." >&2
    exit 1
fi

# Create output directory if needed, then verify it is writable
mkdir -p "$output_dir" 2>/dev/null || true
if [ ! -d "$output_dir" ] || [ ! -w "$output_dir" ]; then
    echo "Error: Output directory '$output_dir' is not writable." >&2
    exit 1
fi

# Create archive directory if needed
mkdir -p "$archive_dir" 2>/dev/null || true
if [ ! -d "$archive_dir" ] || [ ! -w "$archive_dir" ]; then
    echo "Error: Archive directory '$archive_dir' is not writable." >&2
    exit 1
fi

# Analyze a single log file and write summary report
analyze_log() {
    local log_file="$1"
    local base_name
    base_name="$(basename "$log_file" | sed 's/\.[^.]*$//')"
    local date_stamp
    date_stamp="$(date +"%Y-%m-%d_%H%M%S")"
    local summary_file="${output_dir}/summary_${base_name}_${date_stamp}.txt"

    # Check log file exists
    if [ ! -f "$log_file" ]; then
        echo "Error: Log file '$log_file' does not exist." >&2
        return 1
    fi

    local total_lines
    total_lines=$(wc -l < "$log_file")

    # Count errors
    local error_count
    error_count=$(grep -c "$error_keyword" "$log_file" 2>/dev/null || echo "0")

    # Gather critical events with line numbers
    local critical_events
    critical_events=$(grep -n "$critical_keyword" "$log_file" 2>/dev/null || true)
    local critical_count
    if [ -n "$critical_events" ]; then
        critical_count=$(echo "$critical_events" | wc -l | tr -d ' ')
    else
        critical_count=0
    fi

    # Top N error messages by frequency
    local top_errors
    top_errors=$(grep "$error_keyword" "$log_file" 2>/dev/null | awk '{print $1,$2,$3,$4,$5}' | sort | uniq -c | sort -nr | head -n "$top_n" || true)

    # Write summary report
    {
        echo "========================================"
        echo "       LOG ANALYSIS SUMMARY REPORT"
        echo "========================================"
        echo ""
        echo "Date of analysis : $(date +"%Y-%m-%d %H:%M:%S")"
        echo "Log file         : $log_file"
        echo "Total lines      : $total_lines"
        echo "Error keyword    : $error_keyword"
        echo "Critical keyword : $critical_keyword"
        echo "Top N            : $top_n"
        echo ""
        echo "----------------------------------------"
        echo "  ERROR SUMMARY"
        echo "----------------------------------------"
        echo "Total error count: $error_count"
        echo ""
        echo "----------------------------------------"
        echo "  CRITICAL EVENTS (${critical_count} found)"
        echo "----------------------------------------"
        if [ -n "$critical_events" ]; then
            echo "$critical_events"
        else
            echo "(No critical events found)"
        fi
        echo ""
        echo "----------------------------------------"
        echo "  TOP ${top_n} ERROR MESSAGES BY FREQUENCY"
        echo "----------------------------------------"
        if [ -n "$top_errors" ]; then
            echo "$top_errors"
        else
            echo "(No error messages found)"
        fi
        echo ""
        echo "========================================"
        echo "  END OF REPORT"
        echo "========================================"
    } > "$summary_file"

    echo "Summary written to: $summary_file"

    # Archive the processed log
    archive_log "$log_file"
}

# Archive a processed log file, avoiding duplicate archives
archive_log() {
    local log_file="$1"
    local base_name
    base_name="$(basename "$log_file")"
    local dest="${archive_dir}/${base_name}"

    # If already archived (same content), skip
    if [ -f "$dest" ]; then
        if cmp -s "$log_file" "$dest"; then
            echo "Archive: '$base_name' already archived (identical copy exists), skipping."
            return 0
        else
            # Different content, use timestamped name to avoid overwrite
            local ts
            ts="$(date +"%Y%m%d_%H%M%S")"
            dest="${archive_dir}/${base_name%.log}_${ts}.log"
            # Handle non-.log extensions too
            if [[ "$base_name" != *.log ]]; then
                dest="${archive_dir}/${base_name}_${ts}"
            fi
        fi
    fi

    cp "$log_file" "$dest"
    echo "Archive: '$base_name' copied to '$dest'."
}

# Process each log file
exit_code=0
for log_file in "$@"; do
    if ! analyze_log "$log_file"; then
        exit_code=1
    fi
done

exit "$exit_code"
