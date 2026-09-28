#!/usr/bin/env bash
# stages/0_validate.sh <samplesheet.csv> <outdir>
#
# Checks the samplesheet and every input file it names *before* any compute
# happens. Collects every problem across every row, then reports all of them
# together and exits non-zero. Never stops at the first one.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
mkdir -p "$OUTDIR/0_validate"

[[ -f "$SHEET" ]] || die "samplesheet not found: $SHEET"

# fastq_is_truncated <path>
# gzip -t only validates the gzip container's own checksum — a file whose
# FASTQ content was cut off mid-record can still be a perfectly valid,
# properly-closed gzip stream, so gzip -t reports it as fine. A truncated
# FASTQ has to be caught by its content: a record is always exactly four
# lines, so a line count that isn't a multiple of four means the file
# stops partway through a read.
fastq_is_truncated() {
    local path="$1"
    local lines
    # awk's NR counts a last line that has no trailing newline; wc -l would
    # not, so a file cut in the middle of a header would look complete.
    lines=$(gzip -dc "$path" 2>/dev/null | awk 'END{print NR}') || true
    [[ "${lines:-0}" -eq 0 || $((lines % 4)) -ne 0 ]]
}
problems=()
declare -A seen_ids
n_rows=0

while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    n_rows=$((n_rows + 1))
    split_row "$row"

    # duplicate sample_id
    if [[ -n "${seen_ids[$sample_id]:-}" ]]; then
        problems+=("duplicate sample_id '${sample_id}': appears more than once in $SHEET")
    fi
    seen_ids[$sample_id]=1

    # required fields present
    if [[ -z "$sample_id" || -z "$library_type" || -z "$r1_fastq" ]]; then
        problems+=("sample '${sample_id:-<blank>}': missing a required field (sample_id, library_type, or r1_fastq)")
        continue
    fi

    # r1 must exist and be a well-formed gzip stream
    if [[ ! -f "$r1_fastq" ]]; then
        problems+=("sample '${sample_id}': r1_fastq not found: ${r1_fastq}")
    elif ! gzip -t "$r1_fastq" 2>/dev/null; then
        problems+=("sample '${sample_id}': r1_fastq is a truncated or corrupt .fastq.gz: ${r1_fastq}")
    elif fastq_is_truncated "$r1_fastq"; then
        problems+=("sample '${sample_id}': r1_fastq is a truncated .fastq.gz (record count is not a multiple of 4): ${r1_fastq}")
    fi

    # library_type decides whether r2 is required — never the sample's name
    case "$library_type" in
        paired)
            if [[ -z "$r2_fastq" ]]; then
                problems+=("sample '${sample_id}': library_type is 'paired' but r2_fastq is empty")
            elif [[ ! -f "$r2_fastq" ]]; then
                problems+=("sample '${sample_id}': r2_fastq not found: ${r2_fastq}")
            elif ! gzip -t "$r2_fastq" 2>/dev/null; then
                problems+=("sample '${sample_id}': r2_fastq is a truncated or corrupt .fastq.gz: ${r2_fastq}")
            elif fastq_is_truncated "$r2_fastq"; then
                problems+=("sample '${sample_id}': r2_fastq is a truncated .fastq.gz (record count is not a multiple of 4): ${r2_fastq}")
            fi
            ;;
        single)
            if [[ -n "$r2_fastq" ]]; then
                problems+=("sample '${sample_id}': library_type is 'single' but r2_fastq is not empty")
            fi
            ;;
        *)
            problems+=("sample '${sample_id}': library_type must be 'paired' or 'single', got '${library_type}'")
            ;;
    esac
done < <(read_samplesheet "$SHEET")

if [[ "$n_rows" -eq 0 ]]; then
    die "samplesheet has no data rows: $SHEET"
fi

if [[ "${#problems[@]}" -gt 0 ]]; then
    log "validation failed on ${#problems[@]} of ${n_rows} sample(s):"
    for p in "${problems[@]}"; do
        log "  - $p"
    done
    exit 1
fi

log "validated ${n_rows} sample(s) in $SHEET — all inputs present and readable"
