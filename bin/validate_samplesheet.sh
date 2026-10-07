#!/usr/bin/env bash
# validate_samplesheet.sh <samplesheet.csv> <ref.fa> <ref.dict>
#
# Stage 0, run by the VALIDATE process. Week 3's stages/0_validate.sh, changed
# in one way: the task runs in a folder of its own, where Nextflow has linked
# every FASTQ under its file name, so each one is opened by $(basename "$path")
# instead of by the path the samplesheet gives.
#
# Collects every problem across every row, reports them all together, and exits
# non-zero. Never stops at the first one.
set -euo pipefail

SHEET=${1:?usage: validate_samplesheet.sh <samplesheet.csv> <ref.fa> <ref.dict>}
REF=${2:?usage: validate_samplesheet.sh <samplesheet.csv> <ref.fa> <ref.dict>}
DICT=${3:?usage: validate_samplesheet.sh <samplesheet.csv> <ref.fa> <ref.dict>}

# A record is exactly four lines, so a line count that is not a multiple of four
# means the file stops partway -- gzip -t alone can pass a FASTQ cut mid-record.
fastq_is_truncated() {
    local lines
    lines=$(gzip -dc "$1" 2>/dev/null | awk 'END { print NR }') || true
    [[ "${lines:-0}" -eq 0 || $(( lines % 4 )) -ne 0 ]]
}

# The four columns this stage needs, picked BY NAME from the header: the Explorer
# sheet has more columns than the smoke one. CRs stripped, blank lines skipped.
rows() {
    tr -d '\r' < "$SHEET" | awk -F',' -v OFS=',' '
        NR == 1 {
            n = split("sample_id library_type r1_fastq r2_fastq", need, " ")
            for (i = 1; i <= NF; i++) col[$i] = i
            for (j = 1; j <= n; j++)
                if (!(need[j] in col)) { print "samplesheet has no column named " need[j] > "/dev/stderr"; exit 65 }
            next
        }
        !NF { next }
        { print $col["sample_id"], $col["library_type"], $col["r1_fastq"], $col["r2_fastq"] }'
}

problems=()
n_rows=0
declare -A seen=()

rows_out=$(rows)        # an assignment, so a bad header stops the script here
while IFS=',' read -r sample_id library_type r1_path r2_path; do
    n_rows=$(( n_rows + 1 ))

    if [[ -z "$sample_id" || -z "$library_type" || -z "$r1_path" ]]; then
        problems+=("sample '${sample_id:-<blank>}': missing a required field (sample_id, library_type, or r1_fastq)")
        continue
    fi

    if [[ -n "${seen[$sample_id]:-}" ]]; then
        problems+=("duplicate sample_id '${sample_id}': appears more than once in ${SHEET}")
    fi
    seen[$sample_id]=1

    # The file as linked into this task's folder, by its name.
    r1=$(basename "$r1_path")
    r2=""
    [[ -z "$r2_path" ]] || r2=$(basename "$r2_path")

    if [[ ! -e "$r1" ]]; then
        problems+=("sample '${sample_id}': r1_fastq not found: ${r1_path}")
    elif ! gzip -t "$r1" 2>/dev/null; then
        problems+=("sample '${sample_id}': r1_fastq is a truncated or corrupt .fastq.gz: ${r1_path}")
    elif fastq_is_truncated "$r1"; then
        problems+=("sample '${sample_id}': r1_fastq is a truncated .fastq.gz (line count not a multiple of 4)")
    fi

    # library_type decides whether R2 is required -- never the sample's name.
    case "$library_type" in
        paired)
            if [[ -z "$r2" ]]; then
                problems+=("sample '${sample_id}': library_type is paired but r2_fastq is empty")
            elif [[ ! -e "$r2" ]]; then
                problems+=("sample '${sample_id}': r2_fastq not found: ${r2_path}")
            elif ! gzip -t "$r2" 2>/dev/null; then
                problems+=("sample '${sample_id}': r2_fastq is a truncated or corrupt .fastq.gz: ${r2_path}")
            elif [[ -e "$r1" ]]; then
                n1=$(gzip -dc "$r1" 2>/dev/null | awk 'END { print NR }') || true
                n2=$(gzip -dc "$r2" 2>/dev/null | awk 'END { print NR }') || true
                if [[ "${n1:-0}" -ne "${n2:-0}" ]]; then
                    problems+=("sample '${sample_id}': R1 has $(( ${n1:-0} / 4 )) reads, R2 has $(( ${n2:-0} / 4 )) - mates disagree")
                fi
            fi
            ;;
        single)
            if [[ -n "$r2" ]]; then
                problems+=("sample '${sample_id}': library_type is single but r2_fastq is set: ${r2_path}")
            fi
            ;;
        *)
            problems+=("sample '${sample_id}': library_type must be 'paired' or 'single', got '${library_type}'")
            ;;
    esac
done <<< "$rows_out"

if [[ "$n_rows" -eq 0 || -z "$rows_out" ]]; then
    echo "ERROR: samplesheet has no data rows: ${SHEET}" >&2
    exit 1
fi

# The reference, as linked into this folder: GATK needs the .fai and the .dict
# beside the FASTA, BWA its index.
[[ -s "$REF" ]]       || problems+=("reference not found: ${REF}")
[[ -s "${REF}.fai" ]] || problems+=("no samtools index beside the reference: ${REF}.fai")
[[ -s "${REF}.bwt" ]] || problems+=("no BWA index beside the reference: ${REF}.bwt (run: bwa index ${REF})")
[[ -s "$DICT" ]]      || problems+=("no sequence dictionary: ${DICT}")

if [[ "${#problems[@]}" -gt 0 ]]; then
    echo "ERROR: validation failed with ${#problems[@]} problem(s):" >&2
    for p in "${problems[@]}"; do echo "  - $p" >&2; done
    exit 1
fi

echo "validated ${n_rows} sample(s) in ${SHEET}: every input present and readable"
