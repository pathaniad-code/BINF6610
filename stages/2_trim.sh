#!/usr/bin/env bash
# stages/2_trim.sh <samplesheet.csv> <outdir>
# Adapter and quality trimming with fastp. Branches on library_type: a
# paired row gets --in1/--in2/--out1/--out2, a single row gets --in1/--out1
# only. Writes trimmed FASTQs plus fastp's own JSON/HTML report, which
# MultiQC later folds into the cohort report.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
DEST="$OUTDIR/2_trim"
mkdir -p "$DEST"

while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    split_row "$row"

    log "trim: ${sample_id} (${library_type})"

    if [[ "$library_type" == "paired" ]]; then
        fastp \
            --in1 "$r1_fastq" --in2 "$r2_fastq" \
            --out1 "$DEST/${sample_id}.trim_R1.fastq.gz" \
            --out2 "$DEST/${sample_id}.trim_R2.fastq.gz" \
            --json "$DEST/${sample_id}.fastp.json" \
            --html "$DEST/${sample_id}.fastp.html" \
            --thread "$THREADS" \
            >/dev/null
    else
        fastp \
            --in1 "$r1_fastq" \
            --out1 "$DEST/${sample_id}.trim_R1.fastq.gz" \
            --json "$DEST/${sample_id}.fastp.json" \
            --html "$DEST/${sample_id}.fastp.html" \
            --thread "$THREADS" \
            >/dev/null
    fi
done < <(read_samplesheet "$SHEET")

log "trimmed reads written to $DEST"
