#!/usr/bin/env python3
"""score_truth.py <cohort.filtered.vcf.gz> <sample_id>:<truth.txt> [...]

For each sample, counts how many of its planted SNVs (truth lines whose
3rd and 4th columns are both bases, not '-') are called with a
non-reference genotype in the cohort VCF at that position. This is the
same check smoke_0N.truth.txt's README describes and that the acceptance
tests grade against.
"""
import gzip
import sys


def read_vcf_genotypes(vcf_path):
    """Return {sample: {pos: gt}} for every PASS record."""
    opener = gzip.open if vcf_path.endswith(".gz") else open
    genotypes = {}
    with opener(vcf_path, "rt") as f:
        samples = []
        for line in f:
            if line.startswith("##"):
                continue
            if line.startswith("#CHROM"):
                fields = line.rstrip("\n").split("\t")
                samples = fields[9:]
                for s in samples:
                    genotypes[s] = {}
                continue
            fields = line.rstrip("\n").split("\t")
            pos = int(fields[1])
            filt = fields[6]
            if filt != "PASS":
                continue
            for i, s in enumerate(samples):
                gt_field = fields[9 + i].split(":")[0]
                genotypes[s][pos] = gt_field
    return genotypes


def is_non_ref(gt):
    alleles = gt.replace("|", "/").split("/")
    return any(a not in ("0", ".") for a in alleles)


def score_sample(genotypes_for_sample, truth_path):
    total_snvs = 0
    found = 0
    with open(truth_path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 4:
                continue
            _, pos, ref_base, planted = parts[0], int(parts[1]), parts[2], parts[3]
            if ref_base == "-" or planted == "-":
                continue  # indel, not scored here
            total_snvs += 1
            gt = genotypes_for_sample.get(pos)
            if gt and is_non_ref(gt):
                found += 1
    return found, total_snvs


def main():
    vcf_path = sys.argv[1]
    pairs = sys.argv[2:]
    genotypes = read_vcf_genotypes(vcf_path)

    print(f"{'sample':<12}{'found':>8}{'planted_snvs':>15}{'pct':>8}")
    all_pass = True
    for pair in pairs:
        sample, truth_path = pair.split(":", 1)
        if sample not in genotypes:
            print(f"{sample:<12}  ERROR: sample not found in VCF header")
            all_pass = False
            continue
        found, total = score_sample(genotypes[sample], truth_path)
        pct = 100.0 * found / total if total else 0.0
        flag = "" if pct >= 80.0 else "  <-- BELOW 80%"
        if pct < 80.0:
            all_pass = False
        print(f"{sample:<12}{found:>8}{total:>15}{pct:>7.1f}%{flag}")

    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
