#!/usr/bin/env bash
# stages/6_merge.sh <samplesheet.csv> <outdir>
# Joint genotyping across the whole cohort: every sample's GVCF goes into
# one GenomicsDB workspace, then GenotypeGVCFs produces one multi-sample
# VCF. This is where "eight human genomes in, one cohort VCF out" happens —
# it has to see every sample at once, which is why it isn't part of stage 5.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
GVCF_DIR="$OUTDIR/5_quantify"
DEST="$OUTDIR/6_merge"
DB="$DEST/genomicsdb"
mkdir -p "$DEST"
rm -rf "$DB"   # GenomicsDBImport refuses to write into an existing workspace

args=()
while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    split_row "$row"
    args+=(-V "$GVCF_DIR/${sample_id}.g.vcf.gz")
done < <(read_samplesheet "$SHEET")

log "GenomicsDBImport: importing ${#args[@]} GVCF(s) over region ${REGION}"
"$GATK" GenomicsDBImport \
    "${args[@]}" \
    --genomicsdb-workspace-path "$DB" \
    -L "$REGION" \
    --verbosity WARNING \
    2>> "$DEST/genomicsdbimport.log"

log "GenotypeGVCFs: joint genotyping the cohort"
"$GATK" GenotypeGVCFs \
    --reference "$REF" \
    --variant "gendb://$DB" \
    --output "$DEST/cohort.vcf.gz" \
    -L "$REGION" \
    --verbosity WARNING \
    2>> "$DEST/genotypegvcfs.log"

log "joint-genotyped cohort VCF written to $DEST/cohort.vcf.gz"
