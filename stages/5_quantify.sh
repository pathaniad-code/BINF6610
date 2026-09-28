# shellcheck shell=bash
# stages/5_quantify.sh — defines stage_quantify.
# Per-sample variant calling into a GVCF with HaplotypeCaller -ERC GVCF,
# restricted to $REGION. Calling region, not the whole reference, is what
# keeps this fast and (on the real cohort) what keeps a subset reference
# from producing spurious confident calls — see the assignment notes on -L.

stage_quantify() {
    local BAM_DIR="$OUTDIR/4_postprocess" DEST="$OUTDIR/5_quantify" row bam gvcf tmp
    mkdir -p "$DEST"

    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        split_row "$row"

        bam="$BAM_DIR/${sample_id}.dedup.bam"
        gvcf="$DEST/${sample_id}.g.vcf.gz"
        tmp="$DEST/${sample_id}.tmp.g.vcf.gz"
        already_done "$gvcf" && continue

        log "call: ${sample_id} -> GVCF, region ${REGION}"
        "$GATK" HaplotypeCaller \
            --input "$bam" \
            --output "$tmp" \
            --reference "$REF" \
            -L "$REGION" \
            -ERC GVCF \
            --tmp-dir "$TMPDIR" \
            --verbosity WARNING \
            2>> "$DEST/${sample_id}.hc.log"

        mv "$tmp.tbi" "$gvcf.tbi"
        mv "$tmp" "$gvcf"
    done < <(read_samplesheet "$SHEET" "$SAMPLE")

    log "per-sample GVCFs written to $DEST"
}
