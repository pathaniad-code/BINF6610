#!/usr/bin/env bash
# sample_ids.sh <samplesheet.csv> — every sample_id, one per line, in the sheet's order.
# Picked by column name, so it reads the smoke sheet and the Explorer sheet alike.
set -euo pipefail
SHEET=${1:?usage: sample_ids.sh <samplesheet.csv>}
tr -d '\r' < "$SHEET" | awk -F',' '
    NR == 1 {
        for (i = 1; i <= NF; i++) if ($i == "sample_id") c = i
        if (!c) { print "samplesheet has no column named sample_id" > "/dev/stderr"; exit 65 }
        next
    }
    NF && $c != "" { print $c }'
