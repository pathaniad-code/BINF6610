# shellcheck shell=bash
# stages/1_qc_raw.sh — defines stage_qc_raw.
# FastQC on every raw FASTQ named in the samplesheet. One call per file,
# because a paired sample has two files and a single-end sample has one —
# that split comes from library_type, not from counting flags.

stage_qc_raw() {
    local DEST="$OUTDIR/1_qc_raw" row f html
    mkdir -p "$DEST"

    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        split_row "$row"

        for f in "$r1_fastq" ${r2_fastq:+"$r2_fastq"}; do
            [[ "$library_type" == "paired" || "$f" == "$r1_fastq" ]] || continue
            html="$DEST/$(basename "${f%.fastq.gz}")_fastqc.html"
            already_done "$html" && continue
            log "fastqc: ${sample_id} $(basename "$f")"
            fastqc --quiet --dir "$TMPDIR" --outdir "$DEST" "$f"
        done
    done < <(read_samplesheet "$SHEET" "$SAMPLE")

    log "raw QC reports written to $DEST"
}
