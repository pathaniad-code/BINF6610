#!/usr/bin/env bash
# stages/7_analyze.sh <samplesheet.csv> <outdir>
# Hard-filter the joint-genotyped cohort VCF. This is a filter, not a
# subset: records that fail get FILTER != PASS but stay in the file, so
# downstream tools can still see what was called and why it was excluded.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
DEST="$OUTDIR/7_analyze"
mkdir -p "$DEST"

IN="$OUTDIR/6_merge/cohort.vcf.gz"
OUT="$DEST/cohort.filtered.vcf.gz"

log "hard-filtering ${IN}"
"$GATK" VariantFiltration \
    --reference "$REF" \
    --variant "$IN" \
    --output "$OUT" \
    --filter-name "QD2" --filter-expression "QD < 2.0" \
    --filter-name "FS60" --filter-expression "FS > 60.0" \
    --filter-name "MQ40" --filter-expression "MQ < 40.0" \
    --filter-name "SOR3" --filter-expression "SOR > 3.0" \
    --verbosity WARNING \
    2>> "$DEST/variantfiltration.log"

log "filtered cohort VCF written to $OUT"
