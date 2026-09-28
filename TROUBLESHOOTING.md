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

## Stage 0 never looked at the last row of the samplesheet

**Symptom.** The acceptance harness failed two tests that both concern a
truncated `.fastq.gz`:

```
FAIL  stage 0 reports every problem together
      exited 1, but never named: CUTGZIP.
FAIL  catches a truncated .fastq.gz in stage 0
      NA12891's R1 is a gzip stream with its tail cut off and stage 0 accepted it.
```

The second message is the branch the harness reaches only when stage 0
exited **0**. Stage 0 already contained `gzip -t`, so it was not obvious why
a cut-off file got through.

**First theory, tested and rejected.** I assumed `gzip -t` was too weak (it
only checks the gzip container, so FASTQ text cut *before* compression still
passes) and added a "line count is a multiple of 4" check. That is a real
gap, but it was not this bug: the harness result did not change. A sweep of
every possible byte-prefix of a small gzip file showed that *none* of them
pass `gzip -t`, so a genuinely cut-off stream could not have been slipping
past it. The file was not being examined at all.

**Evidence that located the cause.** In the harness source
(`tests/run_acceptance.sh`) `CUTGZIP` is the last of the three broken ids,
and `NA12891` is likewise a row the fixture builds last. Building that shape
of samplesheet by hand, with and without a final newline, and running stage 0
on each:

```
sheet with trailing newline      -> "validation failed ... 'CUTGZIP'"   exit 1
sheet with NO trailing newline   -> "validated 1 sample(s)"             exit 0
```

`tail -c 20 sheet.csv | od -c` confirmed the second sheet ends in `...q.gz`
with no `\n`.

**Cause.** `while IFS= read -r row; do ...; done` returns non-zero on a final
line that has no terminating newline, even though `row` is filled in. The
loop body never runs for that line, so the last sample was never validated
(and, in the later stages, would never have been trimmed, aligned or called).
Nothing failed and nothing was logged, which is why `set -euo pipefail` could
not help: no command returned an error.

**The fix.** Every stage reads the sheet through `read_samplesheet`, so it is
fixed once, there:

```bash
tail -n +2 "$sheet" | tr -d '\r' | awk 'NF'
```

`awk` re-emits each record with a newline (so the last row is delivered),
`tr` strips Windows line endings, and `NF` skips blank lines. I kept the
record-count check in stage 0 as secondary hardening, switching `wc -l` to
`awk 'END{print NR}'` because `wc -l` does not count a dangling last line.

**Lesson.** `set -e` only sees commands that fail. A loop that quietly does
less work than it should is invisible to it, so the check has to be an
assertion on the data: here, that the number of rows processed equals the
number of rows in the file.

## The "truncated" fixture that wasn't truncated

**Symptom.** After fixing the samplesheet loop, the two gzip tests still
failed the same way.

**Evidence.** I built a truncated file by hand and stage 0 caught it and
named the sample — so the check worked. I then rebuilt the harness's own
fixture from `run_acceptance.sh`:

    fq "${FQ}/whole.fastq.gz" 20
    head -c 120 "${FQ}/whole.fastq.gz" > "${FQ}/cut_R1.fastq.gz"

Its 20 records are near-identical, so gzip compresses them to **109
bytes** — and `head -c 120` copies the whole file. `cut_R1.fastq.gz` is
byte-identical to `whole.fastq.gz`: `gzip -t` returns 0, line count a
clean multiple of four. There was nothing to detect.

**Cause.** The fixture's real defect is that `cut_R2` is a copy of a
4-record file while `cut_R1` has 20 — the mates disagree — and my stage 0
had no R1/R2 record-count comparison.

**Fix.** Added that comparison in the `paired)` branch, behind the
existing `-f` and `gzip -t` checks so a missing R2 isn't reported twice,
with the sample id in the message.

**Lesson.** A test's description of what it checks and what it actually
checks can differ. `gzip -t` was the stated route and was unreachable on
my gzip; the check that caught it was the one the assignment names
separately — R1 and R2 agree.
