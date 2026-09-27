#!/usr/bin/env bash
# stages/8_qc_report.sh <samplesheet.csv> <outdir>
# One MultiQC report across the whole cohort, folding together FastQC
# (stage 1), fastp (stage 2), and the dedup metrics (stage 4). Point it at
# the outdir and let it discover everything by file type — no per-sample
# looping needed here.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

OUTDIR="$2"
DEST="$OUTDIR/8_qc_report"
mkdir -p "$DEST"

log "multiqc: scanning $OUTDIR for QC inputs"
multiqc \
    --force \
    --outdir "$DEST" \
    --filename "cohort_multiqc" \
    "$OUTDIR/1_qc_raw" "$OUTDIR/2_trim" "$OUTDIR/4_postprocess" \
    > "$DEST/multiqc.log" 2>&1

log "cohort QC report written to $DEST/cohort_multiqc.html"
