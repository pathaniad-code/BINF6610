#!/usr/bin/env bash
# stages/9_publish.sh <samplesheet.csv> <outdir>
# Turns the run into two tidy, human-readable artifacts: a per-sample TSV
# and results/manifest.json, which records git_sha so a VCF can always be
# traced back to the exact code that produced it.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
DEST="$OUTDIR/9_publish"
mkdir -p "$DEST"

VCF="$OUTDIR/7_analyze/cohort.filtered.vcf.gz"
[[ -f "$VCF" ]] || die "expected filtered VCF not found: $VCF (did stage 7 run?)"

# Decompress once to a plain file. Piping zcat straight into an awk that can
# exit early (e.g. after finding one header line) makes zcat receive
# SIGPIPE, and under pipefail that failure propagates and kills the script —
# so every downstream lookup reads this file instead of re-piping zcat.
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

    # Column for this sample in the cohort VCF; count records that PASS and
    # where this sample has a non-reference genotype.
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

# --- manifest.json ---
MANIFEST="$DEST/manifest.json"
SHA="$(git_sha "$HERE")"
N_SAMPLES=$(read_samplesheet "$SHEET" | grep -c .)

python3 "$HERE/lib/write_manifest.py" "$MANIFEST" "$SHA" "$REF" "$REGION" "$SHEET" "$VCF" "$OUTDIR" "$DEST" "${PIPELINE_STARTED_AT:-}"

log "published $SAMPLES_TSV"
log "published $FILTER_TSV"
log "published $MANIFEST (git_sha=$SHA)"
