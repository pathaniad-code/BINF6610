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

---

# Week 2 — four failures I caused on purpose on Explorer

## 1 · A `--time` that was too short (`--time=00:02:00`)

```bash
sbatch -p courses -A binf6610.202710 --array=1 --time=00:02:00 --export=RUN_TAG=break1 01_persample.sbatch
```
```
           JobID      State ExitCode    Elapsed  Timelimit
      10657548_1    TIMEOUT      0:0   00:02:14   00:02:00
10657548_1.batch  CANCELLED     0:15   00:02:15
[12:25:14] trimmed reads written to /scratch/pathania.d/w2-run-break1/2_trim
[12:25:14] ===== NA12878 · stage 3 : align =====
[12:25:14] align: NA12878 (paired) against /courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa
slurmstepd: error: *** JOB 10657548 ON c0584 CANCELLED AT 2026-09-28T12:26:39 DUE TO TIME LIMIT ***
3_align/:  NA12878.bam.tmp (103,809,024 bytes)   NA12878.bwa.log      <- no NA12878.bam
```

The State is **TIMEOUT**, not FAILED: the script did not error, Slurm stopped it from outside
(`0:15` on the batch step is SIGTERM). My own log gives no reason — it stops mid-stage at
`stage 3 : align`; only Slurm's `slurmstepd` line says why. Elapsed 2:14 overshoots the 2:00
limit because Slurm signals first and waits before killing. On disk, stages 1-2 are complete and
bwa's half-written output is still named `NA12878.bam.tmp`, so no later stage or rerun would
treat it as a finished BAM. The job's `trap` removed `/tmp/10657548`.

## 2 · One task exits 1, with the cohort job on `afterok`

```bash
touch BREAK_TASK_3 && bash submit.sh      # 01_persample.sbatch exits 1 for task 3 when this file exists
```
```
           JobID        JobName      State ExitCode                    Reason
      10657669_1   w2-persample  COMPLETED      0:0                      None
      10657669_2   w2-persample  COMPLETED      0:0                      None
      10657669_3   w2-persample     FAILED      1:0                      None
      10657669_4   w2-persample  COMPLETED      0:0                      None
      10657669_5   w2-persample  COMPLETED      0:0                      None
      10657669_6   w2-persample  COMPLETED      0:0                      None
      10657669_7   w2-persample  COMPLETED      0:0                      None
      10657669_8   w2-persample  COMPLETED      0:0                      None
        10657677      w2-cohort  CANCELLED      0:0                Dependency
task 3: deliberate failure for TROUBLESHOOTING.md
```

Seven of eight samples succeeded and the cohort job never ran: it was **CANCELLED with
Reason=Dependency** within seconds of task 3 failing. That is `afterok` doing its job — with
`afterany` the cohort job would have joint-genotyped seven samples and produced a plausible VCF
of the wrong cohort. Explorer cancels the unsatisfiable dependency by itself; `submit.sh` also
passes `--kill-on-invalid-dep=yes` so a cluster that does not would not leave it PENDING forever.
(Stage 6 additionally refuses to run if any sample's GVCF is missing.)

## 3 · An array wider than the samplesheet (`--array=1-9` on 8 rows)

```bash
ARRAY=1-9 bash submit.sh
```
```
           JobID        JobName      State ExitCode                    Reason
      10657767_1   w2-persample  COMPLETED      0:0                      None
      ...        (tasks 2-8 COMPLETED 0:0)
      10657767_9   w2-persample     FAILED     64:0                      None
        10657786      w2-cohort  CANCELLED      0:0                Dependency
task 9: no row 9 in /courses/BINF6610.202710/data/samplesheet-variant8.csv
```

Task 9 read row 10 of the file, which does not exist, so `$SAMPLE` was empty and the guard in
`01_persample.sbatch` refused it with **exit 64** before anything ran. 64 is a code I chose, so
in `sacct` it cannot be confused with a tool failing. Because task 9 failed, `afterok` also
cancelled the cohort job.

**Without the guard** task 9 would have passed an empty sample name to the pipeline.
`read_samplesheet` treats an empty name as "every row", so task 9 would have run (here: skipped)
stages 0-5 for all eight samples and ended COMPLETED — nine green tasks for eight samples, the
one failure that is silent. `run_sample.sh` has a second check (`no sample_id given`) as a backstop.

## 4 · `scancel` in the middle of a write, then a rerun

I aimed at bwa (stage 3) but align finished (12:44:00 → 12:46:42) before I cancelled, so the
cancel landed in **stage 5, HaplotypeCaller**, 3.5 minutes into writing the GVCF — a tool that
streams its output, which is the dangerous case.

```bash
sbatch -p courses -A binf6610.202710 --array=2 --export=RUN_TAG=break4 01_persample.sbatch
scancel 10657815_2
```
```
      10657815_2 CANCELLED+      0:0   00:07:28
10657815_2.batch  CANCELLED     0:15   00:07:29
[12:47:11] ===== NA12891 · stage 5 : quantify =====
[12:47:11] call: NA12891 -> GVCF, region chr20:1-10000000
slurmstepd: error: *** JOB 10657815 ON c0584 CANCELLED AT 2026-09-28T12:50:38 ***
4_postprocess/: NA12891.dedup.bam (145,478,754)  NA12891.dedup.bam.bai  ...   <- finished, final names
5_quantify/:    NA12891.tmp.g.vcf.gz (15,434,338)  NA12891.hc.log              <- partial, no NA12891.g.vcf.gz
```

Resubmitted the identical job:

```
      10658028_2  COMPLETED      0:0   00:05:20
[12:51:47] skip: NA12891_R1_fastqc.html already exists
[12:51:47] skip: NA12891_R2_fastqc.html already exists
[12:51:47] skip: NA12891.trim_R1.fastq.gz already exists
[12:51:47] skip: NA12891.bam already exists
[12:51:47] skip: NA12891.dedup.bam already exists
[12:51:47] ===== NA12891 · stage 5 : quantify =====
[12:51:47] call: NA12891 -> GVCF, region chr20:1-10000000
[12:56:48] NA12891: done
5_quantify/: NA12891.g.vcf.gz (23,835,745)  NA12891.g.vcf.gz.tbi  NA12891.hc.log
```

**The rerun did not trust what was left behind.** Stages 1-4 skipped in the same second because
their outputs exist under their final names, and HaplotypeCaller ran again from scratch. The
partial GVCF was never mistaken for a finished one because every stage writes to a `.tmp` name
and renames only after the tool exits 0; the skip check looks only for the final name. The
finished GVCF (23.8 MB) is larger than the 15.4 MB fragment, which was a truncated file that a
filename-only check would have accepted.

## Week 3: four failures caused on purpose

### 1. An unpinned recipe rebuilt a day later

In a scratch directory, a recipe with nothing pinned: `FROM ubuntu` (no tag, so whatever `latest` is on build day) and `apt-get install -y curl` (no `=version`).

```
$ cat Dockerfile
FROM ubuntu
RUN apt-get update && apt-get install -y curl

# day 1: base digest, image ID, date
$ docker build --platform linux/amd64 -t tb1:day1 .
$ docker buildx imagetools inspect ubuntu:latest | grep Digest ; docker image inspect --format "{{.Id}}" tb1:day1 ; date
Digest:    sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78
sha256:c3eee9b26f0cc45a6d3374442aa76c456f079f783bb2748c36c8105d8261ad36
Tue Sep 29 13:20:52 EDT 2026

# day 2: a plain rebuild is a cache hit and gives the identical image
$ docker build --platform linux/amd64 -t tb1:plain .
#1 DONE 0.0s
#3 DONE 0.0s
#2 DONE 1.5s
#4 DONE 0.0s
#5 DONE 0.1s
#6 CACHED
#7 DONE 0.2s

# day 2: --pull fetches ubuntu again, --no-cache re-runs apt-get
$ docker build --pull --no-cache --platform linux/amd64 -t tb1:day2 .
Digest:    sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78
sha256:949210d7442654435c5ee2d2bb4489128bcc75acd059a52710cde6add7493dd0
Wed Sep 30 11:06:25 EDT 2026

$ docker run --rm tb1:day1 dpkg -l > day1.txt ; docker run --rm tb1:day2 dpkg -l > day2.txt ; diff day1.txt day2.txt
109c109
< ii  openssl                        3.5.5-1ubuntu3.5                   amd64        Secure Sockets Layer toolkit - cryptographic utility
---
> ii  openssl                        3.5.5-1ubuntu3.6                   amd64        Secure Sockets Layer toolkit - cryptographic utility
```

One package differs after one day: openssl went from `3.5.5-1ubuntu3.5` to `3.5.5-1ubuntu3.6`, a security update. The `ubuntu:latest` digest is the same on both days (`sha256:da6fc2be…`), so the change came entirely from the unpinned `apt-get install`, not from the base image. The two images have different IDs from the same two-line Dockerfile. The plain rebuild reused the cached apt-get layer and would have kept the old openssl without a word; only `--pull --no-cache` picked up the new one.

Fix: tag the base image (never `latest`) and pin every package with `=version`. `containers/Dockerfile` uses `mambaorg/micromamba:2.0.5-ubuntu24.04`, pins all eight tools, and IMAGE.md records the base digest.

### 2. --bind removed from one job script, one sample run

```
$ sed "/--bind/d" slurm/01_persample.sbatch > slurm/tb_nobind.sbatch
$ sbatch -p courses -A binf6610.202710 --array=1 --export=RUN_TAG=nobind tb_nobind.sbatch
$ tail logs/persample_10686333_1.out
job=10686333 task=10686333_1 host=c3014 sample=NA12878 threads=4
/dev/sda12      821G  5.8G  815G   1% /tmp
[13:23:53] ERROR: samplesheet not found: /courses/BINF6610.202710/data/samplesheet-variant8.csv
$ sacct -j 10686333 --format=JobID,State,ExitCode
           JobID      State ExitCode 
---------------- ---------- -------- 
      10686333_1     FAILED      1:0 
10686333_1.batch     FAILED      1:0 
```

It stopped at once, before stage 1, with exit code 1: the pipeline checks the samplesheet first and the container could not see `/courses/BINF6610.202710/data/samplesheet-variant8.csv`. Without `--bind`, Apptainer shows the container only my home directory, `/tmp` and the submit directory; `/courses` (FASTQs, reference, samplesheet) and `/scratch/${USER}` (the run directory) are both invisible. `/courses` is simply the first one the pipeline needs. Because the pipeline checks its inputs up front, this failure is loud; a tool that tolerates a missing input would have carried on and exited 0.

Fix: `--bind "${PIPELINE_DIR}",/scratch/${USER},/courses/BINF6610.202710` on the apptainer exec line of both job scripts.

### 3. --env THREADS removed from one job script, one sample run on 8 cores

```
$ sed "/--env THREADS=/d" slurm/01_persample.sbatch > slurm/tb_nothreads.sbatch
$ sbatch -p courses -A binf6610.202710 --array=1 --cpus-per-task=8 --export=RUN_TAG=nothreads tb_nothreads.sbatch
$ sacct -j 10686334 --format=JobID,State,ExitCode,AllocCPUS
           JobID      State ExitCode  AllocCPUS 
---------------- ---------- -------- ---------- 
      10686334_1  COMPLETED      0:0          8 
10686334_1.batch  COMPLETED      0:0          8 
$ grep "threads=" logs/persample_10686334_1.out ; grep "\[main\] CMD" logs/persample_10686334_1.out
job=10686334 task=10686334_1 host=c0584 sample=NA12878 threads=8
[13:23:52] NA12878: stages validate..quantify  threads=4  tmp=/tmp/10686334
[main] CMD: bwa mem -t 4 -R @RG\tID:NA12878\tSM:NA12878\tLB:NA12878\tPL:ILLUMINA /courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa /scratch/pathania.d/w2-run-nothreads/2_trim/NA12878.trim_R1.fastq.gz /scratch/pathania.d/w2-run-nothreads/2_trim/NA12878.trim_R2.fastq.gz
```

Nothing failed: the job COMPLETED with exit 0. But it was given 8 cores (`AllocCPUS 8`, `threads=8` on the host line) and ran on 4: `--cleanenv` dropped THREADS, the pipeline fell back to its default `THREADS=${THREADS:-4}` in lib/common.sh, and bwa confirms it with `bwa mem -t 4`. Half the cores sat idle, and only the log shows it.

Fix: `--env THREADS="${THREADS}"` (with `--env TMPDIR`) on the apptainer exec line of both job scripts.

### 4. An arm64 image on Explorer

```
$ apptainer pull --arch arm64 arm.sif docker://ubuntu:24.04
$ apptainer exec arm.sif cat /etc/os-release
2026/09/29 13:25:43  info unpack layer: sha256:8a38824eedc553ba80cf1eb7df278a003340f7409fd4b9002bce07db8840a9a2
INFO:    Creating SIF file...
-rwxr-xr-x 1 pathania.d users 28M Sep 29 13:25 arm.sif
FATAL:   While checking container encryption: could not open image /scratch/pathania.d/containers/arm.sif: the image's architecture (arm64) could not run on the host's (amd64)
```

The pull succeeded (a 28 MB arm.sif): Apptainer downloads and converts any architecture without complaint. Running anything from it failed at once, because Explorer is amd64. The same happens to an image built on an Apple-silicon laptop without `--platform`.

Fix: always `docker build --platform linux/amd64`, and check with `docker image inspect --format "{{.Architecture}}"` before pushing.
