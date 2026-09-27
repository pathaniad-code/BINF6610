#!/usr/bin/env bash
# run_pipeline.sh — the driver. Runs stages 0..N in order, stopping after
# the stage named as the third argument (default: run all ten).
#
# Accepted either way:
#   ./run_pipeline.sh samplesheet.csv out validate
#   ./run_pipeline.sh --samplesheet samplesheet.csv --outdir out --to validate

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

STAGE_NAMES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

SAMPLESHEET=""
OUTDIR=""
TO_STAGE="publish"

if [[ "${1:-}" == --* ]]; then
    log "driver form detected: flags"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --samplesheet) SAMPLESHEET="$2"; shift 2 ;;
            --outdir)      OUTDIR="$2";      shift 2 ;;
            --to)          TO_STAGE="$2";    shift 2 ;;
            *) die "unknown flag: $1" ;;
        esac
    done
else
    log "driver form detected: positional"
    SAMPLESHEET="${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last_stage]}"
    OUTDIR="${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last_stage]}"
    TO_STAGE="${3:-publish}"
fi

[[ -f "$SAMPLESHEET" ]] || die "samplesheet not found: $SAMPLESHEET"
mkdir -p "$OUTDIR"
SAMPLESHEET="$(cd "$(dirname "$SAMPLESHEET")" && pwd)/$(basename "$SAMPLESHEET")"
OUTDIR="$(cd "$OUTDIR" && pwd)"

# conf/pipeline.env sets REF and REGION; only those two change between the
# smoke run and the cohort run, and both may already be set in the
# environment (that form is honored: REF=... REGION=... bash run_pipeline.sh ...)
source "$HERE/conf/pipeline.env"
export REF REGION GATK THREADS

log "REF=$REF"
log "REGION=$REGION"
log "outdir=$OUTDIR"

found_stage=0
for name in "${STAGE_NAMES[@]}"; do
    idx=0
    for i in "${!STAGE_NAMES[@]}"; do
        [[ "${STAGE_NAMES[$i]}" == "$name" ]] && idx=$i
    done
    script=$(printf '%s/stages/%d_%s.sh' "$HERE" "$idx" "$name")
    [[ -f "$script" ]] || die "missing stage script: $script"

    log "=== stage ${idx} (${name}) ==="
    bash "$script" "$SAMPLESHEET" "$OUTDIR"

    if [[ "$name" == "$TO_STAGE" ]]; then
        found_stage=1
        log "stopped after stage ${idx} (${name}), as requested"
        break
    fi
done

if [[ "$found_stage" -eq 0 && "$TO_STAGE" != "publish" ]]; then
    die "requested last stage '$TO_STAGE' does not match any known stage: ${STAGE_NAMES[*]}"
fi

log "done."
