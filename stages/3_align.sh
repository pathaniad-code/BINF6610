#!/usr/bin/env bash
# stages/3_align.sh <samplesheet.csv> <outdir>
# BWA-MEM against $REF, reading the trimmed FASTQs stage 2 wrote. The read
# group SM is set to sample_id — that is how every downstream column (the
# GVCF, the joint-genotyped VCF, the QC report) gets matched back to a row
# in the samplesheet.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/common.sh"

SHEET="$1"
OUTDIR="$2"
TRIM_DIR="$OUTDIR/2_trim"
DEST="$OUTDIR/3_align"
mkdir -p "$DEST"

[[ -f "${REF}.bwt" ]] || die "no BWA index next to REF: ${REF}.bwt not found"

while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    split_row "$row"

    rg="@RG\tID:${sample_id}\tSM:${sample_id}\tLB:${sample_id}\tPL:ILLUMINA"
    bam="$DEST/${sample_id}.bam"

    log "align: ${sample_id} (${library_type}) against ${REF}"

    if [[ "$library_type" == "paired" ]]; then
        bwa mem -t "$THREADS" -R "$rg" "$REF" \
            "$TRIM_DIR/${sample_id}.trim_R1.fastq.gz" \
            "$TRIM_DIR/${sample_id}.trim_R2.fastq.gz" \
            2> "$DEST/${sample_id}.bwa.log" \
            | samtools view -b -o "$bam" -
    else
        bwa mem -t "$THREADS" -R "$rg" "$REF" \
            "$TRIM_DIR/${sample_id}.trim_R1.fastq.gz" \
            2> "$DEST/${sample_id}.bwa.log" \
            | samtools view -b -o "$bam" -
    fi
done < <(read_samplesheet "$SHEET")

log "alignments written to $DEST"
