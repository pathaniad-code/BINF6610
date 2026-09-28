# shellcheck shell=bash
# stages/9_publish.sh — defines stage_publish. COHORT STAGE.
# Turns the run into tidy, human-readable artifacts in 9_publish/: the filtered
# cohort VCF, a per-sample TSV, a filter tally, and manifest.json — written by
# the course's lib/write_manifest.sh, which records git_sha so the VCF can
# always be traced back to the exact code that produced it.

stage_publish() {
    local DEST="$OUTDIR/9_publish"
    local VCF="$OUTDIR/7_analyze/cohort.filtered.vcf.gz"
    local VCF_PLAIN SAMPLES_TSV FILTER_TSV row metrics pct_dup col n_called
    mkdir -p "$DEST"
    [[ -f "$VCF" ]] || die "expected filtered VCF not found: $VCF (did stage 7 run?)"

    cp "$VCF" "$VCF.tbi" "$DEST/"

    # Decompress once to a plain file. Piping zcat straight into an awk that can
    # exit early makes zcat receive SIGPIPE, and under pipefail that kills the
    # script — so every lookup below reads this file instead of re-piping zcat.
    VCF_PLAIN="$DEST/.cohort.filtered.vcf"
    zcat "$VCF" > "$VCF_PLAIN"

    # --- samples.tsv: one row per sample, duplication rate + PASS variant count ---
    SAMPLES_TSV="$DEST/samples.tsv"
    printf 'sample_id\tlibrary_type\tpercent_duplication\tpass_variants_called\n' > "$SAMPLES_TSV"

    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        split_row "$row"

        metrics="$OUTDIR/4_postprocess/${sample_id}.dup_metrics.txt"
        pct_dup="NA"
        if [[ -f "$metrics" ]]; then
            pct_dup="$(awk -F'\t' '/^LIBRARY/{getline; print $9}' "$metrics")"
        fi

        col=$(awk -F'\t' -v s="$sample_id" \
            '/^#CHROM/{for(i=10;i<=NF;i++) if($i==s) print i}' "$VCF_PLAIN")
        n_called="NA"
        if [[ -n "$col" ]]; then
            n_called=$(awk -F'\t' -v c="$col" \
                '!/^#/ && $7=="PASS" {split($c,g,":"); if (g[1] != "0/0" && g[1] != "0|0" && g[1] != "./.") n++} END{print n+0}' \
                "$VCF_PLAIN")
        fi

        printf '%s\t%s\t%s\t%s\n' "$sample_id" "$library_type" "$pct_dup" "$n_called" >> "$SAMPLES_TSV"
    done < <(read_samplesheet "$SHEET")

    # --- variants_by_filter.tsv: cohort-wide filter tally ---
    FILTER_TSV="$DEST/variants_by_filter.tsv"
    printf 'filter\tn_records\n' > "$FILTER_TSV"
    awk -F'\t' '!/^#/{print $7}' "$VCF_PLAIN" | sort | uniq -c | awk '{print $2"\t"$1}' >> "$FILTER_TSV"
    rm -f "$VCF_PLAIN"

    # --- manifest.json: the course's script, called the way its header says ---
    bash "$PIPE_DIR/lib/write_manifest.sh" "$DEST" "$SHEET" "$REF" "$REGION"

    log "published $DEST/cohort.filtered.vcf.gz"
    log "published $SAMPLES_TSV"
    log "published $FILTER_TSV"
    log "published $DEST/manifest.json"
}
