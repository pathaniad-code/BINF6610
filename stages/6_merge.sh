# shellcheck shell=bash
# stages/6_merge.sh — defines stage_merge. COHORT STAGE: run_sample.sh refuses it.
# Joint genotyping across the whole cohort: every sample's GVCF goes into
# one GenomicsDB workspace, then GenotypeGVCFs produces one multi-sample
# VCF. This is where "eight human genomes in, one cohort VCF out" happens —
# it has to see every sample at once, which is why it isn't part of stage 5.
#
# The workspace lives in $TMPDIR (the node's own disk): under /scratch the two
# steps took 36-96 min on Explorer, in /tmp about 8. The job's trap removes it.

stage_merge() {
    local GVCF_DIR="$OUTDIR/5_quantify" DEST="$OUTDIR/6_merge"
    local DB="${TMPDIR:-/tmp}/genomicsdb" OUT="$OUTDIR/6_merge/cohort.vcf.gz"
    local TMP_OUT="$OUTDIR/6_merge/cohort.tmp.vcf.gz" row missing=0
    local args=()
    mkdir -p "$DEST"
    already_done "$OUT" && return 0

    # Every sample in the sheet must have its GVCF. Genotyping the ones that
    # happen to be there would give a plausible cohort VCF of the wrong cohort.
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        split_row "$row"
        if [[ -s "$GVCF_DIR/${sample_id}.g.vcf.gz" ]]; then
            args+=(-V "$GVCF_DIR/${sample_id}.g.vcf.gz")
        else
            log "missing GVCF for ${sample_id}"; missing=$((missing + 1))
        fi
    done < <(read_samplesheet "$SHEET")
    [[ "$missing" -eq 0 ]] || die "${missing} sample(s) have no GVCF — refusing to genotype a partial cohort"

    rm -rf "$DB"   # GenomicsDBImport refuses to write into an existing workspace

    log "GenomicsDBImport: importing $(( ${#args[@]} / 2 )) GVCF(s) over region ${REGION}"
    "$GATK" GenomicsDBImport \
        "${args[@]}" \
        --genomicsdb-workspace-path "$DB" \
        -L "$REGION" \
        --tmp-dir "$TMPDIR" \
        --verbosity WARNING \
        2>> "$DEST/genomicsdbimport.log"

    log "GenotypeGVCFs: joint genotyping the cohort"
    "$GATK" GenotypeGVCFs \
        --reference "$REF" \
        --variant "gendb://$DB" \
        --output "$TMP_OUT" \
        -L "$REGION" \
        --tmp-dir "$TMPDIR" \
        --verbosity WARNING \
        2>> "$DEST/genotypegvcfs.log"

    mv "$TMP_OUT.tbi" "$OUT.tbi"
    mv "$TMP_OUT" "$OUT"
    log "joint-genotyped cohort VCF written to $OUT"
}
