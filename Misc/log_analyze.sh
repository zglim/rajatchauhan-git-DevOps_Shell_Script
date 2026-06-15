#!/bin/bash

# log_analyze.sh - Analyze log files and generate summary reports
# Supports custom error/critical keywords, Top N, output directory, and log archiving.

set -euo pipefail

# --------------- Defaults ---------------
error_keyword="ERROR"
critical_keyword="CRITICAL"
top_n=5
output_dir="."
archive_dir="processed_logs"
do_archive=0

# --------------- Usage ---------------
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] <log_file>

Analyze a log file and generate a summary report.

Options:
  -e, --error-keyword <kw>    Keyword to match errors   (default: ERROR)
  -c, --critical-keyword <kw> Keyword to match criticals (default: CRITICAL)
  -n, --top-n <N>             Number of top errors to show (default: 5)
  -o, --output-dir <dir>      Directory for summary report (default: current dir)
  -a, --archive               Archive log to processed_logs after analysis
      --archive-dir <dir>     Archive directory (default: processed_logs)
  -h, --help                  Show this help message

Example:
  $0 -e "ERR" -c "FATAL" -n 10 -o reports -a /var/log/app.log
EOF
    exit 1
}

# --------------- Parse arguments ---------------
log_file=""
while [ $# -gt 0 ]; do
    case "$1" in
        -e|--error-keyword)
            [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; exit 1; }
            error_keyword="$2"; shift 2 ;;
        -c|--critical-keyword)
            [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; exit 1; }
            critical_keyword="$2"; shift 2 ;;
        -n|--top-n)
            [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; exit 1; }
            top_n="$2"; shift 2 ;;
        -o|--output-dir)
            [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; exit 1; }
            output_dir="$2"; shift 2 ;;
        -a|--archive)
            do_archive=1; shift ;;
        --archive-dir)
            [ $# -ge 2 ] || { echo "Error: $1 requires a value" >&2; exit 1; }
            archive_dir="$2"; shift 2 ;;
        -h|--help)
            usage ;;
        -*)
            echo "Error: Unknown option: $1" >&2; exit 1 ;;
        *)
            log_file="$1"; shift ;;
    esac
done

# --------------- Validate inputs ---------------

# Log file must be provided
if [ -z "$log_file" ]; then
    echo "Error: No log file specified." >&2
    usage
fi

# Log file must exist
if [ ! -f "$log_file" ]; then
    echo "Error: Log file '$log_file' does not exist." >&2
    exit 1
fi

# Keywords must not be empty
if [ -z "$error_keyword" ]; then
    echo "Error: Error keyword cannot be empty." >&2
    exit 1
fi
if [ -z "$critical_keyword" ]; then
    echo "Error: Critical keyword cannot be empty." >&2
    exit 1
fi

# Top N must be a positive integer
if ! echo "$top_n" | grep -qE '^[0-9]+$' || [ "$top_n" -le 0 ]; then
    echo "Error: Top N must be a positive integer, got '$top_n'." >&2
    exit 1
fi

# Output directory must exist and be writable; try to create if missing
if [ ! -d "$output_dir" ]; then
    mkdir -p "$output_dir" 2>/dev/null || {
        echo "Error: Cannot create output directory '$output_dir'." >&2
        exit 1
    }
fi
if [ ! -w "$output_dir" ]; then
    echo "Error: Output directory '$output_dir' is not writable." >&2
    exit 1
fi

# --------------- Derived values ---------------
log_basename=$(basename "$log_file")
date_stamp=$(date +"%Y-%m-%d_%H%M%S")
# Summary filename includes original log name + timestamp to avoid collisions
summary_report="${output_dir}/summary_${log_basename}_${date_stamp}.txt"

# --------------- Analysis ---------------
total_lines=$(wc -l < "$log_file" | tr -d ' ')

# Error count
error_count=$(grep -c "$error_keyword" "$log_file" || true)

# Critical events (with line numbers)
critical_events=$(grep -n "$critical_keyword" "$log_file" || true)

# Top N error messages
if [ "$error_count" -gt 0 ]; then
    top_errors=$(grep -i "$error_keyword" "$log_file" | awk '{print $1,$2,$3,$4,$5}' | sort | uniq -c | sort -rn | head -n "$top_n")
else
    top_errors=""
fi

# --------------- Generate report ---------------
{
    echo "====================================="
    echo "        Log Analysis Summary"
    echo "====================================="
    echo ""
    echo "Date of analysis : $(date +"%Y-%m-%d %H:%M:%S")"
    echo "Log file         : $log_file"
    echo "Summary written  : $summary_report"
    echo "Error keyword    : $error_keyword"
    echo "Critical keyword : $critical_keyword"
    echo ""
    echo "-------------------------------------"
    echo "Total lines in log file: $total_lines"
    echo "Total error count ($error_keyword): $error_count"
    echo "-------------------------------------"
    echo ""
    echo "--- Critical Events ($critical_keyword) ---"
    if [ -n "$critical_events" ]; then
        echo "$critical_events"
    else
        echo "(none found)"
    fi
    echo ""
    echo "--- Top $top_n Error Messages ---"
    if [ -n "$top_errors" ]; then
        echo "$top_errors"
    else
        echo "(none found)"
    fi
    echo ""
    echo "====================================="
} > "$summary_report"

echo "Summary report generated: $summary_report"

# --------------- Archive ---------------
if [ "$do_archive" -eq 1 ]; then
    if [ ! -d "$archive_dir" ]; then
        mkdir -p "$archive_dir" 2>/dev/null || {
            echo "Error: Cannot create archive directory '$archive_dir'." >&2
            exit 1
        }
    fi

    # Avoid overwriting an existing archived file with the same name
    archive_target="${archive_dir}/${log_basename}"
    if [ -f "$archive_target" ]; then
        archive_target="${archive_dir}/${log_basename}.${date_stamp}"
    fi

    cp "$log_file" "$archive_target"
    echo "Log archived to: $archive_target"
fi

exit 0
