import csv, datetime, hashlib, json, os, sys

out, sha, ref, region, sheet, vcf, outdir, dest, started = sys.argv[1:10]

def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def checksum(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()

finished = now()
started = started or finished

# samples: straight off the samplesheet, never off a name
samples = []
with open(sheet, newline="") as fh:
    for row in csv.DictReader(fh):
        if not (row.get("sample_id") or "").strip():
            continue
        samples.append({
            "sample_id":    row["sample_id"].strip(),
            "library_type": (row.get("library_type") or "").strip(),
            "condition":    (row.get("condition") or "").strip(),
        })

# outputs: every published artifact, path RELATIVE to outdir
candidates = [
    ("analyze",   "cohort_vcf",             vcf),
    ("publish",   "sample_table",           os.path.join(dest, "samples.tsv")),
    ("publish",   "variant_filter_summary", os.path.join(dest, "variants_by_filter.tsv")),
    ("qc_report", "multiqc",                os.path.join(outdir, "8_qc_report", "cohort_multiqc.html")),
]
outputs = []
for stage, kind, path in candidates:
    if path and os.path.isfile(path):
        outputs.append({"stage": stage, "type": kind,
                        "path": os.path.relpath(path, outdir),
                        "checksum": checksum(path)})

# metrics: long format, one row per (sample, metric)
metrics = []
samples_tsv = os.path.join(dest, "samples.tsv")
if os.path.isfile(samples_tsv):
    with open(samples_tsv, newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            sid = (row.get("sample_id") or "").strip()
            for col, name, stage, unit in (
                ("percent_duplication",  "pct_duplicates",  "postprocess", "percent"),
                ("pass_variants_called", "n_variants_pass", "analyze",     "count"),
            ):
                raw = (row.get(col) or "").strip()
                try:
                    value = float(raw)
                except ValueError:
                    continue          # "NA" is absent, not zero
                metrics.append({"sample_id": sid, "metric": name,
                                "value": value, "unit": unit, "stage": stage})

filter_tsv = os.path.join(dest, "variants_by_filter.tsv")
if os.path.isfile(filter_tsv):
    with open(filter_tsv, newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            if (row.get("filter") or "").strip() == "PASS":
                try:
                    metrics.append({"sample_id": None, "metric": "n_variants_pass",
                                    "value": float(row["n_records"]), "unit": "count",
                                    "stage": "analyze"})
                except (KeyError, ValueError):
                    pass

manifest = {
    "pipeline": {
        "name":           "variant-call",
        "version":        "1.0.0",
        "implementation": "bash",
        "git_sha":        sha or "unknown",
        "run_id":         finished + "-" + (sha or "unknown")[:4],
        "started_at":     started,
        "finished_at":    finished,
        "exit_status":    "success",
    },
    "platform":  {"kind": "laptop"},
    "reference": {"genome": "{}:{}".format(os.path.basename(ref), region)},
    "samples":   samples,
    "outputs":   outputs,
    "metrics":   metrics,
}

with open(out, "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
