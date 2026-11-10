-- Assignment 9 · db/schema.sql
-- Six tables for the variant-call runs of weeks 4-6.
-- Build it with:  sqlite3 runs.db < db/schema.sql

-- A pipeline version. Several runs can share one.
CREATE TABLE pipelines (
    pipeline_id    INTEGER PRIMARY KEY,
    name           TEXT NOT NULL,
    version        TEXT NOT NULL,
    implementation TEXT NOT NULL CHECK (implementation IN ('nextflow', 'snakemake')),
    UNIQUE (name, version, implementation)
) STRICT;

-- One row per run: the facts in manifest.json, and the run's folder.
CREATE TABLE runs (
    run_id      TEXT PRIMARY KEY,                                   -- manifest pipeline.run_id
    pipeline_id INTEGER NOT NULL REFERENCES pipelines (pipeline_id),
    started_at  TEXT NOT NULL,
    finished_at TEXT NOT NULL,
    exit_status TEXT,
    platform    TEXT NOT NULL,                                      -- platform.kind
    executor    TEXT,                                               -- platform.executor
    samplesheet TEXT,                                               -- params.samplesheet
    reference   TEXT,                                               -- params.ref
    region      TEXT,                                               -- params.region
    folder      TEXT NOT NULL                                       -- absolute path
) STRICT;

-- One row per sample: the metadata file's columns.
-- A sample the metadata does not list (the smoke samples) has only its sample_id.
CREATE TABLE samples (
    sample_id              TEXT PRIMARY KEY,
    sex                    TEXT,
    population             TEXT,
    family                 TEXT,
    father                 TEXT,
    mother                 TEXT,
    phenotype              TEXT,
    is_synthetic_phenotype TEXT,
    run                    TEXT,       -- ENA run accession
    read_length            INTEGER,
    bases_gb               REAL,
    study                  TEXT,
    native_layout          TEXT,
    library_type           TEXT
) STRICT;

-- Which samples each run used, and how. The pair is the key: a sample once per run.
CREATE TABLE run_samples (
    run_id       TEXT NOT NULL REFERENCES runs (run_id),
    sample_id    TEXT NOT NULL REFERENCES samples (sample_id),
    condition    TEXT,
    library_type TEXT,
    PRIMARY KEY (run_id, sample_id)
) STRICT;

-- One row per line of a run's variants.tsv.
CREATE TABLE variants (
    run_id     TEXT NOT NULL REFERENCES runs (run_id),
    chrom      TEXT NOT NULL,
    pos        INTEGER NOT NULL CHECK (pos > 0),
    ref        TEXT NOT NULL,
    alt        TEXT NOT NULL,
    qual       REAL,
    filter     TEXT
) STRICT;

-- One row per file in the manifest's outputs. A path once per run.
CREATE TABLE outputs (
    run_id TEXT NOT NULL REFERENCES runs (run_id),
    path   TEXT NOT NULL,
    sha256 TEXT NOT NULL CHECK (length(sha256) = 64),   -- the 64 hex characters, no "sha256:"
    PRIMARY KEY (run_id, path)
) STRICT;

CREATE INDEX variants_by_run ON variants (run_id);
