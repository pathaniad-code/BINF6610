#!/usr/bin/env python3
"""Assignment 9 · db/load.py — load variant-call runs into the SQLite database.

Run from the top of the repository, after db/schema.sql has built the tables:

    python3 db/load.py runs.db db/variant-call-cohort.tsv smoke-run-nf cluster-run-nf ...

The first argument is the database, the second the sample metadata, and every other
argument a run's folder. Each run goes in whole, or not at all; a run whose run_id is
already in the database is skipped, so loading twice changes nothing.
"""
import csv
import json
import os
import sqlite3
import sys

METADATA_COLUMNS = ["sample_id", "sex", "population", "family", "father", "mother",
                    "phenotype", "is_synthetic_phenotype", "run", "read_length",
                    "bases_gb", "study", "native_layout", "library_type"]


def read_tsv(path):
    """Rows of a tab-separated file as dictionaries; lines starting with # are notes."""
    with open(path, newline="") as f:
        lines = [line for line in f if not line.startswith("#")]
    return list(csv.DictReader(lines, delimiter="\t"))


def blank_to_none(value):
    return None if value is None or value.strip() == "" else value


def number(value, kind):
    """int or float of a text value; empty or '.' (VCF's 'no value') becomes NULL."""
    value = blank_to_none(value)
    if value is None or value == ".":
        return None
    return kind(value)


def load_metadata(con, path):
    """Every row of the metadata file into samples, each value as the file writes it."""
    rows = []
    for r in read_tsv(path):
        row = {c: blank_to_none(r.get(c)) for c in METADATA_COLUMNS}
        row["read_length"] = number(r.get("read_length"), int)
        row["bases_gb"] = number(r.get("bases_gb"), float)
        rows.append(tuple(row[c] for c in METADATA_COLUMNS))
    cols = ", ".join(METADATA_COLUMNS)
    marks = ", ".join("?" for _ in METADATA_COLUMNS)
    updates = ", ".join(f"{c} = excluded.{c}" for c in METADATA_COLUMNS[1:])
    # A sample already here (a second load) gets the same values again: nothing changes.
    con.executemany(f"INSERT INTO samples ({cols}) VALUES ({marks})"
                    f" ON CONFLICT (sample_id) DO UPDATE SET {updates}", rows)
    return len(rows)


def load_run(con, folder):
    """Everything one run published. Returns a line saying what happened."""
    with open(os.path.join(folder, "manifest.json")) as f:
        manifest = json.load(f)
    pipeline = manifest["pipeline"]
    params = manifest.get("params", {})
    platform = manifest.get("platform", {})
    run_id = pipeline["run_id"]

    # Loading twice changes nothing: a run that is already here is left as it is.
    if con.execute("SELECT 1 FROM runs WHERE run_id = ?", (run_id,)).fetchone():
        return f"{run_id}: already in the database, skipped"

    # 1. the pipeline version, only if it is new
    version = (pipeline["name"], pipeline["version"], pipeline["implementation"])
    con.execute("INSERT INTO pipelines (name, version, implementation) VALUES (?, ?, ?)"
                " ON CONFLICT (name, version, implementation) DO NOTHING", version)
    pipeline_id = con.execute(
        "SELECT pipeline_id FROM pipelines WHERE name = ? AND version = ? AND implementation = ?",
        version).fetchone()[0]

    # 2. the run: a plain INSERT, so an error undoes the whole run
    con.execute(
        "INSERT INTO runs (run_id, pipeline_id, started_at, finished_at, exit_status,"
        " platform, executor, samplesheet, reference, region, folder)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (run_id, pipeline_id, pipeline["started_at"], pipeline["finished_at"],
         pipeline.get("exit_status"), platform["kind"], platform.get("executor"),
         params.get("samplesheet"), params.get("ref"), params.get("region"),
         os.path.abspath(folder)))

    # 3. a samples row for any sample the metadata does not list (the smoke samples)
    run_samples = manifest["samples"]
    con.executemany("INSERT INTO samples (sample_id) VALUES (?) ON CONFLICT (sample_id) DO NOTHING",
                    [(s["sample_id"],) for s in run_samples])

    # 4. the run's samples: a plain INSERT, so a sample listed twice is refused by the key
    con.executemany(
        "INSERT INTO run_samples (run_id, sample_id, condition, library_type) VALUES (?, ?, ?, ?)",
        [(run_id, s["sample_id"], s.get("condition"), s.get("library_type")) for s in run_samples])

    # 5. its variants, one row for each line of variants.tsv
    variants = [(run_id, v["chrom"], int(v["pos"]), v["ref"], v["alt"],
                 number(v["qual"], float), v["filter"])
                for v in read_tsv(os.path.join(folder, "variants.tsv"))]
    con.executemany(
        "INSERT INTO variants (run_id, chrom, pos, ref, alt, qual, filter)"
        " VALUES (?, ?, ?, ?, ?, ?, ?)", variants)

    # 6. its outputs, with the 64 characters of each checksum
    outputs = [(run_id, o["path"], o["checksum"].lower().replace("sha256:", ""))
               for o in manifest["outputs"]]
    con.executemany("INSERT INTO outputs (run_id, path, sha256) VALUES (?, ?, ?)", outputs)

    return (f"{run_id}: loaded {len(run_samples)} samples, {len(variants)} variants,"
            f" {len(outputs)} files")


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: python3 db/load.py <database> <metadata.tsv> <run folder> ...")
    database, metadata, folders = sys.argv[1], sys.argv[2], sys.argv[3:]

    con = sqlite3.connect(database)
    con.execute("PRAGMA foreign_keys = ON")         # on this connection, every time

    with con:                                       # the metadata, in one transaction
        n = load_metadata(con, metadata)
    print(f"metadata: {n} samples")

    failed = 0
    for folder in folders:
        try:
            with con:                               # one transaction for each run
                print(load_run(con, folder))        # commit at the end; an error undoes it all
        except (sqlite3.Error, KeyError, ValueError, OSError) as e:
            failed += 1
            print(f"{os.path.basename(os.path.normpath(folder))}: refused, nothing loaded ({e})",
                  file=sys.stderr)
    con.close()
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
