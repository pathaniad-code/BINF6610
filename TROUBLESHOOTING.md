# TROUBLESHOOTING — Assignment 5 (Snakemake)

Four failures caused on purpose, each put back afterwards. Last week's four
(Nextflow) are in the Git history of this file.

---

## 1 · Ctrl-C halfway through a laptop run, then the same command again

**Command** (laptop, smoke dataset, from an empty work/, logs/, results/, .snakemake/):

    snakemake --profile profiles/laptop \
        --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb

Stopped with Ctrl-C at `8 of 21 steps (38%) done`, while `bwa_mem` was aligning `smoke_01`.

**What it printed:**

    ^CTerminating processes on user request, this might take some time.
    RuleException:
    CalledProcessError in file "/home/linux/BINF6610/Snakefile", line 210:
    Command 'set -euo pipefail;  (bwa mem -t 4 ... ) 2> logs/bwa_mem/smoke_01.log' died with <Signals.SIGINT: 2>.
    Error in rule bwa_mem:
        jobid: 5
        output: work/align/smoke_01.bam
    WorkflowError:
    At least one job did not complete successfully.

**Then the same command again:** I aimed at an `IncompleteFilesException` telling me to add
`--rerun-incomplete`, and did not get one. The rerun simply planned and ran what was left, and
ended with `13 of 13 steps (100%) done`: 21 jobs minus the 8 that had finished.

**Why:** Ctrl-C stopped Snakemake cleanly, not by killing it. The `bwa_mem` job that was
running died with SIGINT, so Snakemake treated it as a failed job: it deleted its output,
`work/align/smoke_01.bam`, and did not leave it marked incomplete. With nothing marked
incomplete, there was nothing for `--rerun-incomplete` to do. That option is for a run killed
outright (a closed terminal, `kill -9`, a head job that hits its `--time`), which cannot clean
up and leaves the files it was writing marked incomplete; the next run then stops with
`IncompleteFilesException` until it is given `--rerun-incomplete`.

**Fix:** none needed here. Run the same command again; every finished job is reused.

---

## 2 · A log: without {sample}

**Change:** in `rule bwa_mem`, `log: "logs/bwa_mem/{sample}.log"` became `log: "logs/bwa_mem.log"`.

**Command:**

    snakemake --profile profiles/laptop -n --config samplesheet=... ref=... region=smoke_1mb

**What it printed** (before building any plan):

    RuleException in file "/home/linux/BINF6610/Snakefile", line 195:
    Not all output, log and benchmark files of rule bwa_mem contain the same wildcards. This is crucial though, in order to avoid that two or more jobs write to the same file.

**Why:** a wildcard gets its value only from the output, and the output
`work/align/{sample}.bam` has one job per sample. A log with no `{sample}` would be the same
file, `logs/bwa_mem.log`, for all three jobs, which can run at the same time and would overwrite
each other's messages. Snakemake refuses any rule whose output, log and benchmark files do not
have the same wildcards.

**Fix:** put `{sample}` back: `log: "logs/bwa_mem/{sample}.log"`.

---

## 3 · Both wildcard_constraints: deleted from the stage-2 rules

**Change:** deleted `wildcard_constraints: sample=one_of(PAIRED)` from `fastp_paired` and
`wildcard_constraints: sample=one_of(SINGLE)` from `fastp_single`.

**Command:** `snakemake --profile profiles/laptop -n --config ...`, and again asking for one
paired sample's file, `work/trim/smoke_01_R1.trim.fastq.gz`.

**What it printed:**

    AmbiguousRuleException:
    Rules fastp_paired and fastp_single are ambiguous for the file work/trim/smoke_01_R1.trim.fastq.gz.
    Consider starting rule output with a unique prefix, constrain your wildcards, or use the ruleorder directive.
    Wildcards:
            fastp_single: sample=smoke_01
            fastp_paired: sample=smoke_01

**Which rules and which file:** `fastp_paired` and `fastp_single`, for
`work/trim/smoke_01_R1.trim.fastq.gz`.

**Why:** the two rules have the same output names on purpose, so that `bwa_mem` finds a
sample's trimmed reads at one path whether it is paired or not. Without the constraints,
`{sample}` may be anything, so `work/trim/smoke_01_R1.trim.fastq.gz` matches the outputs of
both rules and Snakemake cannot choose between them. The constraints let each sample's name
match only one rule: `smoke_01|smoke_02` for `fastp_paired`, `smoke_03` for `fastp_single`.

**Fix:** put both `wildcard_constraints:` back.

---

## 4 · First Explorer run without software-deployment-method: apptainer

**Change:** deleted `software-deployment-method: apptainer` from
`profiles/explorer/profile.yaml`, on Explorer only (not committed), then
`sbatch slurm/snakemake.sbatch`: head job 10996721.

**What happened:** `validate` finished (`Finished jobid: 7 (Rule: validate)`); then all 8
`fastqc` jobs and all 6 `fastp_paired` jobs failed. The head job had submitted 17 jobs to Slurm
and stopped after 5 min 26 s. Its own log says only that a Slurm job failed:

    Error in rule fastp_paired:
        message: SLURM-job '10996793' failed, SLURM status is: 'FAILED'. Reason: Unknown.
        log: logs/fastp/NA12891.log, .snakemake/slurm_logs/rule_fastp_paired/NA12891/10996793.log
    WorkflowError:
    At least one job did not complete successfully.

**Which rule failed:** `fastp_paired` (and every `fastqc`).

**The exit status**, from that job's own Slurm log,
`.snakemake/slurm_logs/rule_fastp_paired/NA12891/10996793.log`:

    Command 'set -euo pipefail;  fastp --in1 .../NA12891_R1.fastq.gz --in2 .../NA12891_R2.fastq.gz ... --thread 4 2> logs/fastp/NA12891.log' returned non-zero exit status 127.
    srun: error: c0617: task 0: Exited with exit code 1

**What the rule's own log says**, `logs/fastp/NA12891.log` (and `logs/fastqc/NA12878.log`):

    /usr/bin/bash: line 1: fastp: command not found
    /usr/bin/bash: line 1: fastqc: command not found

**Why:** exit status 127 is "command not found". A rule's `container:` is used only when the run
is given `--software-deployment-method apptainer`; without it, each command runs on the bare
compute node, where fastp and fastqc are not installed. `validate` succeeded because it needs
only bash, awk and gzip, which every node has.

**Fix:** put the line back (`git checkout profiles/explorer/profile.yaml`) and submit the same
head job again: head job 10996870, `46 of 46 steps (100%) done` in 28 min 13 s.

**Did validate, which had finished, run again?** Yes. `snakemake -n` after putting the line
back listed it, with:

    rule validate:
        reason: Software environment definition has changed since last execution

It had run outside any image the first time and would now run in the `tools` image, so
Snakemake counts its software environment as changed and redoes it. Everything else had
failed, so the second head job ran all 46 steps.
