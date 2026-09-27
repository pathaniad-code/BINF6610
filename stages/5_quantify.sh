#!/usr/bin/env bash
# stages/5_quantify.sh <samplesheet.csv> <outdir>
# Per-sample variant calling into a GVCF with HaplotypeCaller -ERC GVCF,
# restricted to $REGION. Calling region, not the whole reference, is what
# keeps this fast and (on the real cohort) what keeps a subset reference
# from producing spurious confident calls — see the assignment notes on -L.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
BAM_DIR="$OUTDIR/4_postprocess"
DEST="$OUTDIR/5_quantify"
mkdir -p "$DEST"

while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    split_row "$row"

    bam="$BAM_DIR/${sample_id}.dedup.bam"
    gvcf="$DEST/${sample_id}.g.vcf.gz"

    log "call: ${sample_id} -> GVCF, region ${REGION}"
    "$GATK" HaplotypeCaller \
        --input "$bam" \
        --output "$gvcf" \
        --reference "$REF" \
        -L "$REGION" \
        -ERC GVCF \
        --verbosity WARNING \
        2>> "$DEST/${sample_id}.hc.log"
done < <(read_samplesheet "$SHEET")

log "per-sample GVCFs written to $DEST"
