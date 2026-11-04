# shellcheck shell=bash
# stages/7_analyze.sh — defines stage_analyze. COHORT STAGE.
# Hard-filter the joint-genotyped cohort VCF. This is a filter, not a
# subset: records that fail get FILTER != PASS but stay in the file, so
# downstream tools can still see what was called and why it was excluded.

stage_analyze() {
    local DEST="$OUTDIR/7_analyze"
    local IN="$OUTDIR/6_merge/cohort.vcf.gz"
    local OUT="$DEST/cohort.filtered.vcf.gz" TMP_OUT="$DEST/cohort.filtered.tmp.vcf.gz"
    mkdir -p "$DEST"
    already_done "$OUT" && return 0

    log "hard-filtering ${IN}"
    "$GATK" VariantFiltration \
        --reference "$REF" \
        --variant "$IN" \
        --output "$TMP_OUT" \
        --filter-name "QD2" --filter-expression "QD < 2.0" \
        --filter-name "FS60" --filter-expression "FS > 60.0" \
        --filter-name "MQ40" --filter-expression "MQ < 40.0" \
        --filter-name "SOR3" --filter-expression "SOR > 3.0" \
        --tmp-dir "$TMPDIR" \
        --verbosity WARNING \
        2>> "$DEST/variantfiltration.log"

    mv "$TMP_OUT.tbi" "$OUT.tbi"
    mv "$TMP_OUT" "$OUT"
    log "filtered cohort VCF written to $OUT"
}
