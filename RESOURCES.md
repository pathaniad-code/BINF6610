# RESOURCES.md — what I measured and what I changed

All numbers measured on Explorer's `courses` partition on 2026-09-28, with `seff`, `sacct`
and the cgroup's exact `memory.peak` printed at the end of each job.

## Summary

| Job | First request | Measured | Final request | Why |
|---|---|---|---|---|
| per-sample (array task) | 4 cpu / 16G / 01:00:00 | 2.40 cores busy at 4; wall 5:57–13:30 with all 8 running; memory.peak 11.4–15.0 GB (MaxRSS ~6 GB) | **4 cpu / 20G / 00:30:00** | 4 is the knee (below); raised mem because the worst peak reached 94% of 16G; time cut to ~2.2x the slowest task |
| cohort (stages 6-9) | 4 cpu / 16G / 01:00:00 | 1.04 cores busy; wall 8:00; memory.peak 2.15 GB; CPU efficiency 26.09% | **2 cpu / 4G / 00:30:00** | GenomicsDB/GenotypeGVCFs/VariantFiltration/MultiQC are effectively single-threaded; 4G is ~1.9x the peak |

## Core-count comparison — same sample (task 1, NA12878), changing only --cpus-per-task

Jobs 10656824 (2 cores), 10656828 (4), 10656830 (8); each ran in its own run folder so nothing was skipped.

| --cpus-per-task | Wall-clock | CPU Utilized | busy cores (CPU ÷ wall) | CPU efficiency | core-minutes reserved | memory.peak |
|---|---|---|---|---|---|---|
| 2 | 12:00 | 18:32 | 1.54 | 77.22% | 24.0 | 8.0 GB |
| **4** | **10:24** | 25:01 | **2.40** | 60.14% | 41.6 | 12.9 GB |
| 8 | 8:29 | 24:03 | 2.84 | 35.44% | 67.9 | 13.5 GB |

Per stage, from the log timestamps (mm:ss):

| stage | 2 cores | 4 cores | 8 cores |
|---|---|---|---|
| 0-2 validate + fastqc + fastp | 0:47 | 0:53 | 0:50 |
| 3 align (bwa mem -t, samtools view) | 4:54 | 3:51 | 1:53 |
| 4 sort + MarkDuplicates | 0:34 | 0:33 | 0:31 |
| 5 HaplotypeCaller (-L chr20:1-10 Mb) | 5:35 | 4:59 | 4:54 |

## Decision

Only bwa uses the extra cores: align drops from 4:54 to 1:53 as cores go 2 → 8, while
HaplotypeCaller takes ~5 min whatever it is given and is half of every task. Going from 4 to 8
cores saved only 1:55 per sample but reserved 26 more core-minutes (≈3.5 core-hours across 8
samples) at 35% efficiency, so I kept **--cpus-per-task=4** rather than raising it.

`seff`'s "Memory Utilized" (MaxRSS) was only ~6 GB, but the exact cgroup `memory.peak` was
11.4–15.0 GB with all eight tasks running at once (it also counts file cache from reading the
FASTQs and the 3 GB reference). The worst task reached 14.96 GB — 94% of 16G. Explorer does not
kill a job for exceeding --mem, but most clusters do, so I **raised --mem from 16G to 20G**
(~1.3x the worst peak).

The slowest task in the full run took 13:30 (task 7), so I **reduced --time from 1:00:00 to
0:30:00** — about 2.2x, enough for a busier node without holding a slot for an hour.

The cohort job kept 1.04 of its 4 cores busy (8:21 CPU over 8:00 wall) and peaked at 2.15 GB, so I
**cut it down from 4 cpu / 16G / 1h to 2 cpu / 4G / 30 min**.

## Full run with these settings (array 10657113, cohort 10657121)

```
           JobID      State    Elapsed  AllocCPUS
      10657113_1  COMPLETED   00:08:30          4
      10657113_2  COMPLETED   00:09:12          4
      10657113_3  COMPLETED   00:06:52          4
      10657113_4  COMPLETED   00:08:09          4
      10657113_5  COMPLETED   00:05:57          4
      10657113_6  COMPLETED   00:08:55          4
      10657113_7  COMPLETED   00:13:30          4
      10657113_8  COMPLETED   00:10:21          4
        10657121  COMPLETED   00:08:00          4
task 1: memory.peak bytes: 13740445696
task 2: memory.peak bytes: 14963347456
task 3: memory.peak bytes: 11362324480
task 4: memory.peak bytes: 12684677120
task 5: memory.peak bytes: 11375915008
task 6: memory.peak bytes: 13683085312
task 7: memory.peak bytes: 14510841856
task 8: memory.peak bytes: 13748555776
```

Result: 36,853 records in chr20:1-10 Mb (36,077 PASS), 17,373–18,515 PASS non-reference calls per sample.

## Raw seff output

```
== 2 cores: seff 10656824_1
State: COMPLETED (exit code 0)
Cores per node: 2
CPU Utilized: 00:18:32
CPU Efficiency: 77.22% of 00:24:00 core-walltime
Job Wall-clock time: 00:12:00
Memory Utilized: 5.80 GB
Memory Efficiency: 36.27% of 16.00 GB
memory.peak bytes: 8010399744

== 4 cores: seff 10656828_1
State: COMPLETED (exit code 0)
Cores per node: 4
CPU Utilized: 00:25:01
CPU Efficiency: 60.14% of 00:41:36 core-walltime
Job Wall-clock time: 00:10:24
Memory Utilized: 5.98 GB
Memory Efficiency: 37.37% of 16.00 GB
memory.peak bytes: 12890193920

== 8 cores: seff 10656830_1
State: COMPLETED (exit code 0)
Cores per node: 8
CPU Utilized: 00:24:03
CPU Efficiency: 35.44% of 01:07:52 core-walltime
Job Wall-clock time: 00:08:29
Memory Utilized: 6.28 GB
Memory Efficiency: 39.27% of 16.00 GB
memory.peak bytes: 13545828352

== cohort: seff 10657121
State: COMPLETED (exit code 0)
Cores per node: 4
CPU Utilized: 00:08:21
CPU Efficiency: 26.09% of 00:32:00 core-walltime
Job Wall-clock time: 00:08:00
Memory Utilized: 2.01 GB
Memory Efficiency: 12.54% of 16.00 GB
memory.peak bytes: 2154790912
```
