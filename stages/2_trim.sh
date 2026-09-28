# shellcheck shell=bash
# stages/2_trim.sh — defines stage_trim.
# Adapter and quality trimming with fastp. Branches on library_type: a
# paired row gets --in1/--in2/--out1/--out2, a single row gets --in1/--out1
# only. Writes trimmed FASTQs plus fastp's own JSON/HTML report, which
# MultiQC later folds into the cohort report.
# Outputs are written under a .tmp name and renamed when fastp exits 0; R1 is
# renamed last, so its final name means the whole sample is done.

stage_trim() {
    local DEST="$OUTDIR/2_trim" row o1 o2
    mkdir -p "$DEST"

    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        split_row "$row"
        o1="$DEST/${sample_id}.trim_R1.fastq.gz"
        o2="$DEST/${sample_id}.trim_R2.fastq.gz"
        already_done "$o1" && continue

        log "trim: ${sample_id} (${library_type})"

        if [[ "$library_type" == "paired" ]]; then
            fastp \
                --in1 "$r1_fastq" --in2 "$r2_fastq" \
                --out1 "$DEST/${sample_id}.trim_R1.tmp.fastq.gz" \
                --out2 "$DEST/${sample_id}.trim_R2.tmp.fastq.gz" \
                --json "$DEST/${sample_id}.fastp.json" \
                --html "$DEST/${sample_id}.fastp.html" \
                --thread "$THREADS" \
                >/dev/null
            mv "$DEST/${sample_id}.trim_R2.tmp.fastq.gz" "$o2"
        else
            fastp \
                --in1 "$r1_fastq" \
                --out1 "$DEST/${sample_id}.trim_R1.tmp.fastq.gz" \
                --json "$DEST/${sample_id}.fastp.json" \
                --html "$DEST/${sample_id}.fastp.html" \
                --thread "$THREADS" \
                >/dev/null
        fi
        mv "$DEST/${sample_id}.trim_R1.tmp.fastq.gz" "$o1"
    done < <(read_samplesheet "$SHEET" "$SAMPLE")

    log "trimmed reads written to $DEST"
}
