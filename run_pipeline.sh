#!/usr/bin/env bash
# run_pipeline.sh — the whole cohort. Runs stages in order, every sample.
#
# Accepted either way:
#   bash run_pipeline.sh samplesheet.csv out [last_stage]
#   bash run_pipeline.sh --samplesheet samplesheet.csv --outdir out [--from merge] [--to publish]
#
# On the laptop it runs all ten stages. On Explorer the cohort job calls it with
# --from merge, after the array has run stages 0-5 for every sample.
# For ONE sample, which is what an array task needs, use run_sample.sh — it
# calls exactly the same stage functions.

set -euo pipefail
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # write_manifest.sh records it
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"
for f in "$HERE"/stages/*.sh; do source "$f"; done

STAGE_NAMES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

SHEET=""
OUTDIR=""
FROM_STAGE="validate"
TO_STAGE="publish"
SAMPLE=""                      # empty means "every sample"

if [[ "${1:-}" == --* ]]; then
    log "driver form detected: flags"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --samplesheet) SHEET="$2";      shift 2 ;;
            --outdir)      OUTDIR="$2";     shift 2 ;;
            --from)        FROM_STAGE="$2"; shift 2 ;;
            --to)          TO_STAGE="$2";   shift 2 ;;
            *) die "unknown flag: $1" ;;
        esac
    done
else
    log "driver form detected: positional"
    SHEET="${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last_stage]}"
    OUTDIR="${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last_stage]}"
    TO_STAGE="${3:-publish}"
fi

[[ -f "$SHEET" ]] || die "samplesheet not found: $SHEET"
mkdir -p "$OUTDIR"
SHEET="$(cd "$(dirname "$SHEET")" && pwd)/$(basename "$SHEET")"
OUTDIR="$(cd "$OUTDIR" && pwd)"

# stage name -> index; both ends must be real stage names
from_idx=-1; to_idx=-1
for i in "${!STAGE_NAMES[@]}"; do
    [[ "${STAGE_NAMES[$i]}" == "$FROM_STAGE" ]] && from_idx=$i
    [[ "${STAGE_NAMES[$i]}" == "$TO_STAGE" ]] && to_idx=$i
done
(( from_idx >= 0 )) || die "unknown stage '$FROM_STAGE': ${STAGE_NAMES[*]}"
(( to_idx >= 0 ))   || die "unknown stage '$TO_STAGE': ${STAGE_NAMES[*]}"

log "REF=$REF"
log "REGION=$REGION"
log "outdir=$OUTDIR  threads=$THREADS  tmp=$TMPDIR"

for (( i = from_idx; i <= to_idx; i++ )); do
    log "=== stage ${i} (${STAGE_NAMES[$i]}) ==="
    "stage_${STAGE_NAMES[$i]}"
done

log "done."
