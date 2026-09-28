#!/usr/bin/env bash
# run_sample.sh — stages 0 to 5, for ONE sample.
#
#   bash run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last_stage]
#
# This is what a Slurm array task runs: the scheduler picks the sample, this
# runs the pipeline on it. It calls exactly the same stage functions as
# run_pipeline.sh — which is why the stages live in stages/.
#
# It refuses to go past stage 5 (quantify) on purpose. merge, analyze,
# qc_report and publish are cohort stages: they need every sample, and a
# single task cannot know whether the other seven have finished.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"
for f in "$HERE"/stages/*.sh; do source "$f"; done

SHEET=${1:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last_stage]}
OUTDIR=${2:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last_stage]}
SAMPLE=${3:-}
LAST=${4:-quantify}

# An empty name would select EVERY row in read_samplesheet — refuse it.
[[ -n "$SAMPLE" ]] || die "no sample_id given"

PER_SAMPLE=(validate qc_raw trim align postprocess quantify)
known=0
for stage in "${PER_SAMPLE[@]}"; do [[ "$stage" == "$LAST" ]] && known=1; done
(( known )) || die "run_sample.sh stops at quantify; '${LAST}' is a cohort stage (merge/analyze/qc_report/publish need every sample)"

[[ -f "$SHEET" ]] || die "samplesheet not found: $SHEET"
[[ -n "$(read_samplesheet "$SHEET" "$SAMPLE")" ]] || die "no sample '${SAMPLE}' in ${SHEET}"
mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"

log "${SAMPLE}: stages validate..${LAST}  threads=${THREADS}  tmp=${TMPDIR}"
n=0
for stage in "${PER_SAMPLE[@]}"; do
    log "===== ${SAMPLE} · stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "${SAMPLE}: done"
