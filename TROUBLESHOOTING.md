# TROUBLESHOOTING.md

## Stage 9 (publish) exited 141 with no error message

**Symptom.** A full run of `run_pipeline.sh` on the smoke dataset completed
stages 0–8 normally — `7_analyze/cohort.filtered.vcf.gz` and
`8_qc_report/cohort_multiqc.html` were both present and correct — but the
run stopped partway through stage 9 with exit code 141 and no line in the
log saying what went wrong. `results/manifest.json` and `samples.tsv` were
never written.

**Evidence that located the cause.** 141 is 128+13, i.e. the process was
killed by `SIGPIPE`. The only place stage 9 reads a large stream is the
per-sample loop that extracts each sample's column index from the VCF
header:

```bash
col=$(zcat "$VCF" | awk -F'\t' -v s="$sample_id" \
    '/^#CHROM/{for(i=10;i<=NF;i++) if($i==s) print i; exit}')
```

Running the two halves of that pipe separately showed the problem:
`awk` finds the `#CHROM` line near the top of the file, prints the column
number, and calls `exit` immediately — while `zcat` is still partway
through decompressing and writing the rest of the ~30 MB VCF into the
pipe. `awk` closing its end early makes the next `write()` from `zcat`
raise `EPIPE`, and `zcat` is killed by `SIGPIPE`. Under `set -o pipefail`
the pipeline's exit status is `zcat`'s (141), and under `set -e` that
propagates to the whole script — so the script died on the very first
sample, before any output file was opened.

**The fix.** Stage 9 now decompresses the filtered VCF to a temporary
plain-text file once, and every subsequent lookup — the column-index scan
and the per-sample genotype count — reads that file instead of re-invoking
`zcat` in a pipe that can be cut short:

```bash
VCF_PLAIN="$DEST/.cohort.filtered.vcf"
zcat "$VCF" > "$VCF_PLAIN"
col=$(awk -F'\t' -v s="$sample_id" \
    '/^#CHROM/{for(i=10;i<=NF;i++) if($i==s) print i}' "$VCF_PLAIN")
```

`awk` can now finish reading a real file (or not — either way there's no
process on the other end to receive `SIGPIPE`), and the temp file is
removed at the end of the stage.

**Lesson for the rest of the pipeline.** `set -euo pipefail` catches a
failed command, but it does not protect against a *successful* command
(`awk`) triggering a spurious failure in an upstream command it's piped
from. Any stage script that pipes a large decompression into a filter
that might `exit` before consuming all its input has the same exposure —
worth grepping for `zcat .* | .*exit` in the other stages before this
pattern bites again somewhere else.
