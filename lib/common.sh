#!/usr/bin/env bash
# lib/common.sh — sourced by run_pipeline.sh and run_sample.sh (never executed).
# What every stage needs: the settings, log and die, and reading the
# samplesheet by column name. The stages themselves live in stages/.

set -euo pipefail

PIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- settings -----------------------------------------------------------------
# REF and REGION moved here from conf/pipeline.env: both entry points need them.
# A job starts the pipeline with nothing in front of bash, so the Explorer values
# are the defaults. On the laptop: REF=/path/smoke.fa REGION=smoke_1mb bash run_pipeline.sh ...
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
GATK=${GATK:-gatk}
THREADS=${THREADS:-4}       # the Slurm job script sets it from SLURM_CPUS_PER_TASK
TMPDIR=${TMPDIR:-/tmp}      # the Slurm job script sets it to /tmp/<jobid>
export REF REGION GATK THREADS TMPDIR

# log <message>   — progress goes to stderr (fd 2), stdout stays clean for data.
log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

die() {
    printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
    exit 1
}

# read_samplesheet <path> [sample_id]
# One line per data row, header stripped, as
#   sample_id,condition,replicate,library_type,r1_fastq,r2_fastq
# The columns are picked BY NAME from the header: the Explorer sheet has ten
# columns, and reading it by position would put columns 6-10 into r2_fastq.
# Given a sample_id, only that row is emitted (the array-task case).
#  - awk re-emits every record with a newline, so a last row with no trailing
#    newline is still delivered.
#  - tr strips CRs, so a sheet saved with Windows line endings parses too.
#  - blank lines are skipped.
read_samplesheet() {
    local sheet="$1" only="${2:-}"
    [[ -f "$sheet" ]] || die "samplesheet not found: $sheet"
    tr -d '\r' < "$sheet" | awk -F',' -v OFS=',' -v want="$only" '
        NR == 1 {
            n = split("sample_id condition replicate library_type r1_fastq r2_fastq", need, " ")
            for (i = 1; i <= NF; i++) col[$i] = i
            for (j = 1; j <= n; j++)
                if (!(need[j] in col)) { print "samplesheet has no column named " need[j] > "/dev/stderr"; exit 65 }
            next
        }
        !NF { next }
        want != "" && $col["sample_id"] != want { next }
        { print $col["sample_id"], $col["condition"], $col["replicate"],
                $col["library_type"], $col["r1_fastq"], $col["r2_fastq"] }'
}

# split a data row into named vars: sample_id, condition, replicate,
# library_type, r1_fastq, r2_fastq. IFS set to comma only for this read,
# so a value containing a space (like "Donor 3-rep1") survives intact.
split_row() {
    local row="$1"
    IFS=',' read -r sample_id condition replicate library_type r1_fastq r2_fastq <<< "$row"
}

# already_done <file> — true if a stage's FINAL output exists. Every stage writes
# to a *.tmp name and renames only after the tool exits 0, so a file under its
# final name is always complete, and a rerun redoes anything that was cut off.
already_done() {
    [[ -s "$1" ]] && { log "skip: $(basename "$1") already exists"; return 0; }
    return 1
}
