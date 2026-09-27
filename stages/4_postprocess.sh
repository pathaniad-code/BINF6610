#!/usr/bin/env bash
# stages/4_postprocess.sh <samplesheet.csv> <outdir>
# Coordinate-sort, index, and mark duplicates on every sample's BAM from
# stage 3. GATK needs the .bai to exist next to the BAM it reads.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
ALIGN_DIR="$OUTDIR/3_align"
DEST="$OUTDIR/4_postprocess"
mkdir -p "$DEST"

while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    split_row "$row"

    raw_bam="$ALIGN_DIR/${sample_id}.bam"
    sorted_bam="$DEST/${sample_id}.sorted.bam"
    dedup_bam="$DEST/${sample_id}.dedup.bam"
    metrics="$DEST/${sample_id}.dup_metrics.txt"

    log "sort: ${sample_id}"
    samtools sort -@ "$THREADS" -o "$sorted_bam" "$raw_bam"
    samtools index "$sorted_bam"

    log "mark duplicates: ${sample_id}"
    "$GATK" MarkDuplicates \
        --INPUT "$sorted_bam" \
        --OUTPUT "$dedup_bam" \
        --METRICS_FILE "$metrics" \
        --QUIET true \
        --VERBOSITY WARNING \
        2>> "$DEST/${sample_id}.markdup.log"

    samtools index "$dedup_bam"
done < <(read_samplesheet "$SHEET")

log "sorted, indexed, deduplicated BAMs written to $DEST"
