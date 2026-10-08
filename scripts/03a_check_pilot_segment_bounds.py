# ============================================================
# 03a_check_pilot_segment_bounds.py
#
# Preflight the pilot training segments before audio extraction.
#
# This script:
#   1. reads the Script 02 manifest
#   2. records the 3 researcher-approved unresolved exclusions
#   3. checks all remaining segments against actual WAV lengths
#   4. confirms the one known boundary failure
#   5. records all 4 pilot exclusions
#   6. writes a final 570-row extraction-eligible manifest
#
# It does NOT extract any WAV files.
# ============================================================

import csv
import os
import wave

from collections import defaultdict
from decimal import Decimal
from pathlib import Path


# ------------------------------------------------------------
# 1. Paths
# ------------------------------------------------------------

MANIFEST_PATH = Path(
    "output/manifest/02_pilot_segment_manifest.csv"
)

AUDIO_ROOTS = [
    Path("D:/2025 ARU Data"),
    Path("D:/2025 King Rail Project/Choctaw_WMA_2025 Data"),
    Path("D:/2025 King Rail Project/AGL ARU Data/Audio"),
]

EXCLUSION_RECORD_PATH = Path(
    "output/qc/03a_pilot_excluded_segments.csv"
)

ELIGIBLE_MANIFEST_PATH = Path(
    "output/manifest/03a_pilot_segment_manifest_eligible.csv"
)


# ------------------------------------------------------------
# 2. Researcher-approved unresolved reviewed exclusions
# ------------------------------------------------------------

REVIEW_OUTCOME_EXCLUSIONS = {
    (
        "MINI06_20250411_100002.wav",
        Decimal("60"),
    ),
    (
        "SMA06000_20250417_062900.wav",
        Decimal("531"),
    ),
    (
        "SMA06000_20250417_062900.wav",
        Decimal("1494"),
    ),
}


# ------------------------------------------------------------
# 3. Researcher-approved boundary exclusion
# ------------------------------------------------------------
#
# Preflight showed that this Background parent starts at
# 3597.428 s in a WAV that ends at 3598.000 s.
#
# Only 0.572 s of the requested 3-second segment exists.
# The next recording begins after a 2-second recording gap.
#
# Researcher decision:
# exclude rather than shorten, pad, or stitch.

EXPECTED_BOUNDARY_EXCLUSIONS = {
    (
        "MINI06_20250412_110002.wav",
        Decimal("3597.428"),
    ),
}


# ------------------------------------------------------------
# 4. Helper
# ------------------------------------------------------------

def segment_id(row):
    return (
        row["Begin File"].strip(),
        Decimal(
            row["parent_start"].strip()
        ),
    )


# ------------------------------------------------------------
# 5. Read Script 02 manifest
# ------------------------------------------------------------

with MANIFEST_PATH.open(
    "r",
    newline="",
    encoding="utf-8-sig",
) as f:

    manifest = list(
        csv.DictReader(f)
    )


if not manifest:
    raise RuntimeError(
        "Manifest is empty."
    )


print(
    f"Original manifest segments: "
    f"{len(manifest)}"
)


# ------------------------------------------------------------
# 6. Confirm the 3 unresolved reviewed exclusions
# ------------------------------------------------------------

observed_zero_label_reviewed = {
    segment_id(row)
    for row in manifest
    if (
        row["segment_type"] == "reviewed"
        and int(
            row["n_model_labels"]
        ) == 0
    )
}


if (
    observed_zero_label_reviewed
    != REVIEW_OUTCOME_EXCLUSIONS
):

    raise RuntimeError(
        "Reviewed zero-label segments no longer "
        "match the 3 researcher-approved exclusions."
    )


print(
    "Reviewed outcome exclusions confirmed: "
    f"{len(REVIEW_OUTCOME_EXCLUSIONS)}"
)


# ------------------------------------------------------------
# 7. Build candidate set for boundary checking
# ------------------------------------------------------------
#
# Remove the 3 already-approved unresolved segments first.

boundary_candidates = [
    row
    for row in manifest
    if segment_id(row)
    not in REVIEW_OUTCOME_EXCLUSIONS
]


print(
    f"Segments to boundary-check: "
    f"{len(boundary_candidates)}"
)


# ------------------------------------------------------------
# 8. Locate required source WAVs
# ------------------------------------------------------------

required_files = {
    row["Begin File"].strip()
    for row in boundary_candidates
}

matches = {
    name: []
    for name in required_files
}


for root in AUDIO_ROOTS:

    print(
        f"Searching: {root}"
    )

    for dirpath, _, filenames in os.walk(root):

        for filename in filenames:

            if filename in matches:

                matches[
                    filename
                ].append(
                    Path(dirpath)
                    / filename
                )


source_lookup = {}

for filename, paths in matches.items():

    if len(paths) != 1:

        raise RuntimeError(
            f"{filename} has "
            f"{len(paths)} source matches; "
            "expected exactly 1."
        )

    source_lookup[
        filename
    ] = paths[0]


print(
    "Unique source recordings resolved: "
    f"{len(source_lookup)}"
)


# ------------------------------------------------------------
# 9. Group segments by source recording
# ------------------------------------------------------------

segments_by_file = defaultdict(
    list
)

for row in boundary_candidates:

    segments_by_file[
        row["Begin File"].strip()
    ].append(row)


# ------------------------------------------------------------
# 10. Check every requested 3-second segment
#     against actual WAV duration
# ------------------------------------------------------------

failures = []


for begin_file, rows in segments_by_file.items():

    source_path = source_lookup[
        begin_file
    ]

    with wave.open(
        str(source_path),
        "rb",
    ) as source:

        sample_rate = (
            source.getframerate()
        )

        total_frames = (
            source.getnframes()
        )

        recording_duration = (
            total_frames
            / sample_rate
        )

        frames_per_clip = (
            3 * sample_rate
        )

        for row in rows:

            parent_start = float(
                row["parent_start"]
            )

            start_frame = round(
                parent_start
                * sample_rate
            )

            end_frame = (
                start_frame
                + frames_per_clip
            )

            if end_frame > total_frames:

                available_seconds = (
                    total_frames
                    - start_frame
                ) / sample_rate

                failures.append(
                    {
                        "Begin File":
                            begin_file,
                        "segment_type":
                            row[
                                "segment_type"
                            ],
                        "parent_start":
                            row[
                                "parent_start"
                            ],
                        "recording_duration":
                            recording_duration,
                        "available_seconds":
                            available_seconds,
                        "missing_seconds":
                            3
                            - available_seconds,
                        "model_labels":
                            row[
                                "model_labels"
                            ],
                    }
                )


# ------------------------------------------------------------
# 11. Report boundary failures
# ------------------------------------------------------------

print()
print(
    "========== BOUNDARY PREFLIGHT =========="
)

print(
    f"Segments checked: "
    f"{len(boundary_candidates)}"
)

print(
    "Segments extending beyond source WAV: "
    f"{len(failures)}"
)


for row in failures:

    print()

    print(
        f"{row['Begin File']} | "
        f"start {row['parent_start']} | "
        f"type {row['segment_type']}"
    )

    print(
        "  recording duration: "
        f"{row['recording_duration']:.6f} s"
    )

    print(
        "  available audio: "
        f"{row['available_seconds']:.6f} s"
    )

    print(
        "  missing audio: "
        f"{row['missing_seconds']:.6f} s"
    )

    print(
        "  labels: "
        f"{row['model_labels']}"
    )


# ------------------------------------------------------------
# 12. Confirm boundary failures match researcher decision
# ------------------------------------------------------------

observed_boundary_exclusions = {
    (
        row["Begin File"],
        Decimal(
            str(
                row["parent_start"]
            )
        ),
    )
    for row in failures
}


if (
    observed_boundary_exclusions
    != EXPECTED_BOUNDARY_EXCLUSIONS
):

    raise RuntimeError(
        "Observed boundary failures do not match "
        "the researcher-approved boundary exclusion."
    )


print()
print(
    "Boundary exclusion confirmed: "
    f"{len(EXPECTED_BOUNDARY_EXCLUSIONS)}"
)


# ------------------------------------------------------------
# 13. Combine all approved exclusions
# ------------------------------------------------------------

ALL_APPROVED_EXCLUSIONS = (
    REVIEW_OUTCOME_EXCLUSIONS
    | EXPECTED_BOUNDARY_EXCLUSIONS
)


# ------------------------------------------------------------
# 14. Create final extraction-eligible manifest
# ------------------------------------------------------------

eligible_final = [
    row
    for row in manifest
    if segment_id(row)
    not in ALL_APPROVED_EXCLUSIONS
]


reviewed_final = sum(
    row["segment_type"] == "reviewed"
    for row in eligible_final
)

background_final = sum(
    row["segment_type"] == "Background"
    for row in eligible_final
)


# Expected pilot totals after all 4 exclusions.

if len(eligible_final) != 570:
    raise RuntimeError(
        f"Expected 570 eligible segments; "
        f"found {len(eligible_final)}."
    )

if reviewed_final != 434:
    raise RuntimeError(
        f"Expected 434 reviewed segments; "
        f"found {reviewed_final}."
    )

if background_final != 136:
    raise RuntimeError(
        f"Expected 136 Background segments; "
        f"found {background_final}."
    )


# ------------------------------------------------------------
# 15. Build exclusion record
# ------------------------------------------------------------

manifest_lookup = {
    segment_id(row): row
    for row in manifest
}


review_reason = (
    "Done = 1 parent with no resolved biological "
    "label or Verify outcome; excluded from pilot."
)

boundary_reason = (
    "3-second parent extends beyond available source "
    "WAV into an unrecorded inter-file gap; "
    "excluded from pilot."
)


exclusion_records = []


for identity in sorted(
    ALL_APPROVED_EXCLUSIONS
):

    source_row = manifest_lookup[
        identity
    ]

    begin_file, parent_start = (
        identity
    )

    if (
        identity
        in EXPECTED_BOUNDARY_EXCLUSIONS
    ):

        reason = boundary_reason

    else:

        reason = review_reason


    exclusion_records.append(
        {
            "segment_type":
                source_row[
                    "segment_type"
                ],
            "Begin File":
                begin_file,
            "parent_start":
                str(parent_start),
            "reason":
                reason,
        }
    )


# ------------------------------------------------------------
# 16. Write exclusion record
# ------------------------------------------------------------

EXCLUSION_RECORD_PATH.parent.mkdir(
    parents=True,
    exist_ok=True,
)


with EXCLUSION_RECORD_PATH.open(
    "w",
    newline="",
    encoding="utf-8",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=[
            "segment_type",
            "Begin File",
            "parent_start",
            "reason",
        ],
    )

    writer.writeheader()

    writer.writerows(
        exclusion_records
    )


# ------------------------------------------------------------
# 17. Write final eligible manifest
# ------------------------------------------------------------
#
# Script 02's authoritative manifest remains untouched.

ELIGIBLE_MANIFEST_PATH.parent.mkdir(
    parents=True,
    exist_ok=True,
)


with ELIGIBLE_MANIFEST_PATH.open(
    "w",
    newline="",
    encoding="utf-8",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=
            manifest[0].keys(),
    )

    writer.writeheader()

    writer.writerows(
        eligible_final
    )


# ------------------------------------------------------------
# 18. Final summary
# ------------------------------------------------------------

print()
print(
    "========== PILOT EXCLUSION SUMMARY =========="
)

print(
    "Reviewed outcome exclusions: "
    f"{len(REVIEW_OUTCOME_EXCLUSIONS)}"
)

print(
    "Boundary exclusions: "
    f"{len(EXPECTED_BOUNDARY_EXCLUSIONS)}"
)

print(
    "Total exclusions: "
    f"{len(ALL_APPROVED_EXCLUSIONS)}"
)

print()

print(
    "Eligible reviewed segments: "
    f"{reviewed_final}"
)

print(
    "Eligible Background segments: "
    f"{background_final}"
)

print(
    "Final extraction segments: "
    f"{len(eligible_final)}"
)

print()

print(
    f"Exclusion record:\n"
    f"{EXCLUSION_RECORD_PATH}"
)

print()

print(
    f"Eligible manifest:\n"
    f"{ELIGIBLE_MANIFEST_PATH}"
)

print(
    "============================================="
)
