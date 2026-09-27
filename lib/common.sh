#!/usr/bin/env bash
# lib/common.sh — sourced by run_pipeline.sh and every stage script.
# Never sourced twice with different REF/REGION in one run.

set -euo pipefail

# log <message>   — progress goes to stderr (fd 2), stdout stays clean for data.
log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

die() {
    printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
    exit 1
}

# read_samplesheet <path>
# Emits one line per data row, tab-separated, with the header stripped.
# Never echoes a sample id anywhere except through this data path — the
# calling code branches on $library_type, never on $sample_id.
read_samplesheet() {
    local sheet="$1"
    tail -n +2 "$sheet"
}

# split a CSV data row into named vars: sample_id, condition, replicate,
# library_type, r1_fastq, r2_fastq. IFS set to comma only for this read,
# so a value containing a space (like "Donor 3-rep1") survives intact.
split_row() {
    local row="$1"
    IFS=',' read -r sample_id condition replicate library_type r1_fastq r2_fastq <<< "$row"
}

# git_sha <repo_root>
# Prints the commit the working tree was run at, or "unknown" if there is
# no commit yet, or "<sha>-dirty" if the tree has changed since that commit.
# This is what tells someone reading results/manifest.json which code
# actually produced the VCF next to it.
git_sha() {
    local root="$1"
    if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        echo "unknown"
        return
    fi
    if ! git -C "$root" rev-parse HEAD >/dev/null 2>&1; then
        echo "unknown"
        return
    fi
    local sha
    sha="$(git -C "$root" rev-parse --short HEAD)"
    if [[ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]]; then
        echo "${sha}-dirty"
    else
        echo "$sha"
    fi
}
