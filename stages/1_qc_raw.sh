#!/usr/bin/env bash
# stages/1_qc_raw.sh <samplesheet.csv> <outdir>
# FastQC on every raw FASTQ named in the samplesheet. One call per file,
# because a paired sample has two files and a single-end sample has one —
# that split comes from library_type, not from counting flags.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
DEST="$OUTDIR/1_qc_raw"
mkdir -p "$DEST"

while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    split_row "$row"

    log "fastqc: ${sample_id} R1"
    fastqc --quiet --outdir "$DEST" "$r1_fastq"

    if [[ "$library_type" == "paired" ]]; then
        log "fastqc: ${sample_id} R2"
        fastqc --quiet --outdir "$DEST" "$r2_fastq"
    fi
done < <(read_samplesheet "$SHEET")

log "raw QC reports written to $DEST"
