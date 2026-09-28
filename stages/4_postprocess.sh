# shellcheck shell=bash
# stages/4_postprocess.sh — defines stage_postprocess.
# Coordinate-sort, index, and mark duplicates on every sample's BAM from
# stage 3. GATK needs the .bai to exist next to the BAM it reads.
# samtools sort spills temporary files beside its output by default — on the
# cluster that is shared network storage — so -T points them at $TMPDIR, the
# node's own disk.

stage_postprocess() {
    local ALIGN_DIR="$OUTDIR/3_align" DEST="$OUTDIR/4_postprocess"
    local row raw_bam sorted_bam dedup_bam tmp_bam metrics
    mkdir -p "$DEST"

    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        split_row "$row"

        raw_bam="$ALIGN_DIR/${sample_id}.bam"
        sorted_bam="$DEST/${sample_id}.sorted.bam"
        dedup_bam="$DEST/${sample_id}.dedup.bam"
        tmp_bam="$DEST/${sample_id}.dedup.tmp.bam"
        metrics="$DEST/${sample_id}.dup_metrics.txt"
        already_done "$dedup_bam" && continue

        log "sort: ${sample_id}"
        samtools sort -@ "$THREADS" -T "${TMPDIR}/sort_${sample_id}" -o "$sorted_bam" "$raw_bam"
        samtools index "$sorted_bam"

        log "mark duplicates: ${sample_id}"
        "$GATK" MarkDuplicates \
            --INPUT "$sorted_bam" \
            --OUTPUT "$tmp_bam" \
            --METRICS_FILE "$metrics" \
            --TMP_DIR "$TMPDIR" \
            --QUIET true \
            --VERBOSITY WARNING \
            2>> "$DEST/${sample_id}.markdup.log"

        samtools index "$tmp_bam" "$tmp_bam.bai"
        mv "$tmp_bam.bai" "$dedup_bam.bai"
        mv "$tmp_bam" "$dedup_bam"
    done < <(read_samplesheet "$SHEET" "$SAMPLE")

    log "sorted, indexed, deduplicated BAMs written to $DEST"
}
