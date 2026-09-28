# shellcheck shell=bash
# stages/8_qc_report.sh — defines stage_qc_report. COHORT STAGE.
# One MultiQC report across the whole cohort, folding together FastQC
# (stage 1), fastp (stage 2), and the dedup metrics (stage 4).

stage_qc_report() {
    local DEST="$OUTDIR/8_qc_report"
    mkdir -p "$DEST"

    log "multiqc: scanning $OUTDIR for QC inputs"
    multiqc \
        --force \
        --outdir "$DEST" \
        --filename "cohort_multiqc" \
        "$OUTDIR/1_qc_raw" "$OUTDIR/2_trim" "$OUTDIR/4_postprocess" \
        > "$DEST/multiqc.log" 2>&1

    log "cohort QC report written to $DEST/cohort_multiqc.html"
}
