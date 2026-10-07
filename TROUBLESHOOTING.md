# TROUBLESHOOTING.md — Assignment 4 (Nextflow)

Four failures caused on purpose. Weeks 1–3's entries are in the Git history.

---

## 1 · Ctrl-C halfway through a smoke run, then `-resume`

**Command.**

```bash
nextflow run main.nf -profile docker -ansi-log false \
    --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb
# Ctrl-C just after "Submitted process > MARKDUPLICATES (smoke_03)"
nextflow run main.nf -profile docker -ansi-log false -resume \
    --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb
```

**What it printed** (the -resume run):

```text
[68/385c07] Cached process > VALIDATE
[35/f740a4] Cached process > FASTQC (smoke_02)
[5e/f32e4a] Cached process > FASTP (smoke_03)
[b0/4bbff9] Cached process > FASTP (smoke_01)
[6c/e3c92f] Cached process > FASTQC (smoke_01)
[ba/3b39bb] Cached process > FASTQC (smoke_03)
[aa/011c49] Cached process > FASTP (smoke_02)
[d8/685019] Cached process > BWA_MEM (smoke_03)
[24/5b2942] Submitted process > BWA_MEM (smoke_02)
[73/9c46e5] Submitted process > BWA_MEM (smoke_01)
[db/6ce1a1] Submitted process > MARKDUPLICATES (smoke_03)
[a7/7e63de] Submitted process > HAPLOTYPECALLER (smoke_03)
[59/9d7058] Submitted process > MARKDUPLICATES (smoke_02)
[0d/2a5de0] Submitted process > MARKDUPLICATES (smoke_01)
[67/8b6728] Submitted process > HAPLOTYPECALLER (smoke_02)
[8d/dbd001] Submitted process > MULTIQC
[3a/84d8ad] Submitted process > HAPLOTYPECALLER (smoke_01)
[22/6fef51] Submitted process > JOINT_GENOTYPE
[0b/0c7fb4] Submitted process > FILTER
[53/5577a2] Submitted process > PUBLISH
```

**What was cached and what ran again.** 8 tasks were cached: VALIDATE,
FASTQC ×3, FASTP ×3 and BWA_MEM (smoke_03) — the ones that had finished
before Ctrl-C. Their work folders are the same as in the interrupted run
(VALIDATE is 68/385c07 in both). BWA_MEM for smoke_01 and smoke_02 was still
running when I pressed Ctrl-C, and MARKDUPLICATES (smoke_03) had just started,
so those ran again, with everything downstream of them: 12 tasks in all. A
task is cached only when its work folder finished with exit 0 and its script
and inputs hash the same; a killed task never wrote its `.exitcode`. PUBLISH
always reruns: it has `cache false`.

**Fix.** Nothing to fix — `-resume` is my week 1–3 skip-if-done test
(`already_done`), done by Nextflow from the work/ cache.

---

## 2 · The reference given as a queue channel to BWA_MEM

**Command.** In `main.nf`, stage 3 only:

```groovy
BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)
```

then the smoke run with `-resume`.

**What it printed.**

```text
[73/9c46e5] Cached process > BWA_MEM (smoke_01)
[0d/2a5de0] Cached process > MARKDUPLICATES (smoke_01)
[3a/84d8ad] Cached process > HAPLOTYPECALLER (smoke_01)
[68/e38d1a] Submitted process > JOINT_GENOTYPE
ERROR ~ Error executing process > 'JOINT_GENOTYPE'
  Process `JOINT_GENOTYPE` terminated with an error exit status (1)
Command error:
  missing GVCF for smoke_02
  missing GVCF for smoke_03
  2 sample(s) have no GVCF - refusing to genotype a partial cohort
```

**What happened.** BWA_MEM ran for one sample only, smoke_01; smoke_02 and
smoke_03 never reached stage 3. `channel.fromPath(params.ref)` is a queue
channel holding the FASTA once: the first sample consumed it, and the other
two waited for a reference that never came. (smoke_01's BWA_MEM was even
cached: the reference is the same file either way, so that task's hash was
unchanged — only the number of tasks changed.) The run did not stop at
BWA_MEM; JOINT_GENOTYPE stopped it, because its check found 2 samples without
a GVCF. Without that check, the run would have "succeeded" with a one-sample
cohort VCF.

**Fix.** Put back `ref`, the value channel from `file(params.ref)`, which
every sample can read as often as it needs:
`BWA_MEM(FASTP.out.reads, ref, ref_index)`.

---

## 3 · The backslash taken off one `\$(…)`

**Command.** In `modules/joint_genotype.nf`, line 44:
`tmp=\$(mktemp -d …)` → `tmp=$(mktemp -d …)`, then the smoke run with `-resume`.

**What it printed.** Every task up to HAPLOTYPECALLER was cached; JOINT_GENOTYPE ran and failed:

```text
ERROR ~ Error executing process > 'JOINT_GENOTYPE'
  Process `JOINT_GENOTYPE` terminated with an error exit status (2)
Command executed:
  tmp=smoke_1mbmktemp -d "${TMPDIR:-/tmp}/genomicsdb.XXXXXX")
  ...
      -L smoke.fa \
  ...
      --reference smoke_1mb \
  ...
      -L  \
Command error:
  .command.sh: line 19: syntax error near unexpected token `)'
Work dir:
  /home/linux/BINF6610/work/06/5ba2a632d07cbbfef488d17a02c9e0
```

**From the task's work folder.**

- `.command.sh`, lines 17–21 — the script Nextflow wrote for bash:
```text
  fi

  tmp=smoke_1mbmktemp -d "${TMPDIR:-/tmp}/genomicsdb.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
```
  Nextflow read the unescaped `$(` as one of its own placeholders and filled
  it with a value, so every `${…}` after it got the value meant for the one
  before: `tmp=` got the region (`smoke_1mb`), GenomicsDBImport's `-L` got the
  FASTA name (`smoke.fa`), GenotypeGVCFs' `--reference` got the region, and
  its `-L` was left empty.
- `.command.err`:
  `.command.sh: line 19: syntax error near unexpected token ')'`
- `bash .command.run` in that folder, which reruns the task by hand in the
  same container without Nextflow, printed the same line-19 syntax error and
  exited 2. So the fault is in the script text Nextflow generated, not in
  GATK and not in Nextflow's running of it. Nextflow did not catch it; bash did.

**Fix.** Put the backslash back: inside a script block every `$` meant for
bash is written `\$`, so Nextflow leaves it for bash.

---

## 4 · A two-minute time limit on HAPLOTYPECALLER, first Explorer run

**Command.** In the explorer profile of `nextflow.config`, uncommented:

```groovy
withName: 'HAPLOTYPECALLER' {
    time = '2m'
}
```

then `sbatch slurm/nextflow.sbatch` (head job 10898237).

**What it printed** (`nf-head-10898237.out`):

```text
ERROR ~ Error executing process > 'HAPLOTYPECALLER (NA12003)'
Caused by:
  Process `HAPLOTYPECALLER (NA12003)` terminated with an error exit status (140)
Command exit status:
  140
Work dir:
  /home/pathania.d/BINF6610/work/2f/bef8f6d483fc64135f2bb2e10a8832
```

`results/pipeline_info/trace.txt`: NA12003 `FAILED 140`, native_id 10898509,
realtime 1m 27s; the other seven HAPLOTYPECALLER tasks `ABORTED`.

**sacct.**

```text
JobID                               JobName      State ExitCode    Elapsed  Timelimit
10898509       nf-HAPLOTYPECALLER_(NA12003)     FAILED     12:0   00:01:29   00:02:00
10898509.ba+                          batch     FAILED     12:0   00:01:29
10898542       nf-HAPLOTYPECALLER_(NA12891) CANCELLED+      0:0   00:00:40   00:02:00
10898542.ba+                          batch     FAILED     15:0   00:00:42
```

**What happened.** Exit status 140, not a Slurm TIMEOUT. Nextflow submits
each task asking Slurm to send it SIGUSR2 30 seconds before its time limit,
and stops the task when that warning arrives. So the job ended at 00:01:29,
under its Timelimit of 00:02:00; sacct records State FAILED with ExitCode 12
(SIGUSR2 is signal 12), and Nextflow reports 128 + 12 = 140. One failed task
stopped the run: Nextflow cancelled the seven other HaplotypeCaller jobs
(10898542 shows CANCELLED at 00:00:40, its batch step ending on SIGTERM, 15).
Compare week 2, where my own job script hit the limit and sacct said TIMEOUT.

**Fix.** Commented the `time = '2m'` block out again, so HAPLOTYPECALLER
gets the profile's `1h`, and resubmitted (head job 10898704). `-resume`
reused every task that had finished — VALIDATE, FASTQC, FASTP, BWA_MEM,
MARKDUPLICATES — and the run carried on from HaplotypeCaller. `time`, `cpus`
and `memory` are not part of a task's hash, which is why this had to be done
on the first run: a finished task would never have rerun to hit the limit.

