# shellcheck shell=bash
# stages/0_validate.sh — defines stage_validate. Sourced by both entry points.
#
# Checks the samplesheet and every input file it names *before* any compute
# happens. Collects every problem across every row, then reports all of them
# together and exits non-zero. Never stops at the first one.
# Uses: SHEET, SAMPLE (empty = every row).

# fastq_is_truncated <path>
# gzip -t only validates the gzip container's own checksum — a file whose
# FASTQ content was cut off mid-record can still be a perfectly valid,
# properly-closed gzip stream. A record is always exactly four lines, so a
# line count that isn't a multiple of four means the file stops partway.
fastq_is_truncated() {
    local path="$1"
    local lines
    lines=$(gzip -dc "$path" 2>/dev/null | awk 'END{print NR}') || true
    [[ "${lines:-0}" -eq 0 || $((lines % 4)) -ne 0 ]]
}

stage_validate() {
    local problems=() n_rows=0 row n1 n2
    local -A seen_ids=()

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
            problems+=("sample '${sample_id}': r1_fastq is a truncated .fastq.gz (record count not multiple of 4)")
        fi

        # library_type decides whether r2 is required — never the sample's name
        case "$library_type" in
            paired)
                if [[ -z "$r2_fastq" ]]; then
                    problems+=("sample '${sample_id}': library_type is paired but r2_fastq is empty")
                elif [[ ! -f "$r2_fastq" ]]; then
                    problems+=("sample '${sample_id}': r2_fastq not found: ${r2_fastq}")
                elif ! gzip -t "$r2_fastq" 2>/dev/null; then
                    problems+=("sample '${sample_id}': r2_fastq is a truncated or corrupt .fastq.gz: ${r2_fastq}")
                else
                    n1=$(gzip -dc "$r1_fastq" 2>/dev/null | awk 'END{print NR}') || true
                    n2=$(gzip -dc "$r2_fastq" 2>/dev/null | awk 'END{print NR}') || true
                    if [[ "${n1:-0}" -ne "${n2:-0}" ]]; then
                        problems+=("sample '${sample_id}': R1 has $(( ${n1:-0} / 4 )) reads, R2 has $(( ${n2:-0} / 4 )) — mates disagree")
                    fi
                fi
                ;;
            single)
                if [[ -n "$r2_fastq" ]]; then
                    problems+=("sample '${sample_id}': library_type is single but r2_fastq is set: ${r2_fastq}")
                fi
                ;;
            *)
                problems+=("sample '${sample_id}': library_type must be 'paired' or 'single', got '${library_type}'")
                ;;
        esac
    done < <(read_samplesheet "$SHEET" "$SAMPLE")

    if [[ "$n_rows" -eq 0 ]]; then
        die "samplesheet has no data rows${SAMPLE:+ for sample '$SAMPLE'}: $SHEET"
    fi

    if [[ "${#problems[@]}" -gt 0 ]]; then
        log "validation failed on ${#problems[@]} of ${n_rows} sample(s):"
        local p
        for p in "${problems[@]}"; do log "  - $p"; done
        exit 1
    fi

    log "validated ${n_rows} sample(s) in $SHEET — all inputs present and readable"
}
