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

## Stage 0 accepted a truncated `.fastq.gz` that it should have rejected

**Symptom.** Running the official acceptance harness (`tests/run_acceptance.sh`)
against a passing-looking build showed two failures instead of nine passes:

```
FAIL  stage 0 reports every problem together
      exited 1, but never named: CUTGZIP. A stage 0 that dies on the first
      problem costs one run per typo. Collect them, then exit once.
FAIL  catches a truncated .fastq.gz in stage 0
      NA12891's R1 is a gzip stream with its tail cut off and stage 0
      accepted it. 'gzip -t' is the check; the file opens fine and ends
      in the middle.
```

Both failures came from the same root cause: one of the harness's four
broken fixture samples is a `.fastq.gz` that was truncated in a specific
way, and stage 0 let it through.

**Evidence that located the cause.** Reproducing the fixture by hand —
cutting a real FASTQ off after 1,000 whole reads plus one extra line,
then re-gzipping the result — showed the gap directly:

```bash
zcat smoke_01_R1.fastq.gz | head -n 4001 | gzip > cut_mid_record.fastq.gz
gzip -t cut_mid_record.fastq.gz; echo $?      # -> 0  (gzip is satisfied!)
zcat cut_mid_record.fastq.gz | wc -l          # -> 4001
```

`gzip -t` only verifies the gzip *container's* own checksum. If the
FASTQ content is cut off after the container was closed properly — i.e.
the truncation happened before compression, not to the compressed
stream itself — the result is a perfectly valid gzip file that just
happens to hold an incomplete last record. `gzip -t` has nothing to
object to, because from its point of view nothing is wrong: the CRC
matches the bytes that are there. The problem is entirely at the FASTQ
level: 4001 lines is one line short of a whole number of 4-line records.

**The fix.** Stage 0 now checks record completeness in addition to
container integrity — a FASTQ's line count must be a multiple of 4:

```bash
fastq_is_truncated() {
    local path="$1"
    local lines
    lines=$(gzip -dc "$path" 2>/dev/null | wc -l)
    [[ $((lines % 4)) -ne 0 ]]
}
```

This runs after `gzip -t` for each of `r1_fastq` and `r2_fastq`, so a
corrupt gzip container is still caught first (cheaper check, clearer
message), and a truncated-but-valid-gzip FASTQ is now caught too.

**Lesson.** "The file is valid" and "the file is complete" are different
claims, and a format's own integrity check (gzip's CRC) only proves the
first one. Any validation step that wraps a container format around
something with its own structure (FASTQ's 4-line records, in this case)
needs a second check at the inner format's level — checking the outer
format alone leaves exactly this gap.
