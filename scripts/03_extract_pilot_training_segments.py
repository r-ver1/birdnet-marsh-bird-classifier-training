# ============================================================
# 03_extract_pilot_training_segments.py
#
# Extract the final Script 03a-approved pilot manifest into
# exact 3-second WAV clips.
#
# Script 03a already handled and documented pilot exclusions.
# This script therefore extracts ONLY the 570 eligible segments.
#
# Source WAVs are never modified.
# ============================================================

import csv
import os
import wave

from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


# ------------------------------------------------------------
# 1. Paths
# ------------------------------------------------------------

MANIFEST_PATH = Path(
    "output/manifest/03a_pilot_segment_manifest_eligible.csv"
)

AUDIO_ROOTS = [
    Path("D:/2025 ARU Data"),
    Path("D:/2025 King Rail Project/Choctaw_WMA_2025 Data"),
    Path("D:/2025 King Rail Project/AGL ARU Data/Audio"),
]

OUTPUT_ROOT = Path(
    "output/training_segments/pilotKIRA"
)

REVIEWED_DIR = OUTPUT_ROOT / "reviewed"
BACKGROUND_DIR = OUTPUT_ROOT / "background"

QC_PATH = (
    OUTPUT_ROOT /
    "03_extraction_qc.csv"
)


# ------------------------------------------------------------
# 2. Helpers
# ------------------------------------------------------------

def decimal_value(row, column):
    return Decimal(
        row[column].strip()
    )


def decimal_text(value):
    text = format(value, "f")

    if "." in text:
        text = text.rstrip("0").rstrip(".")

    return text


# ------------------------------------------------------------
# 3. Read eligible manifest
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
        "Eligible manifest is empty."
    )


print(
    f"Eligible manifest segments: "
    f"{len(manifest)}"
)


if len(manifest) != 570:
    raise RuntimeError(
        f"Expected 570 eligible segments; "
        f"found {len(manifest)}."
    )


reviewed_count = sum(
    row["segment_type"] == "reviewed"
    for row in manifest
)

background_count = sum(
    row["segment_type"] == "Background"
    for row in manifest
)


if reviewed_count != 434:
    raise RuntimeError(
        f"Expected 434 reviewed segments; "
        f"found {reviewed_count}."
    )

if background_count != 136:
    raise RuntimeError(
        f"Expected 136 Background segments; "
        f"found {background_count}."
    )


print(
    f"Reviewed segments: {reviewed_count}"
)

print(
    f"Background segments: {background_count}"
)


# ------------------------------------------------------------
# 4. Do not mix with an earlier extraction
# ------------------------------------------------------------

if OUTPUT_ROOT.exists():

    raise RuntimeError(
        f"Output directory already exists:\n"
        f"{OUTPUT_ROOT}\n\n"
        "Rename or remove it before running Script 03."
    )


# ------------------------------------------------------------
# 5. Locate required source WAVs
# ------------------------------------------------------------

required_files = {
    row["Begin File"].strip()
    for row in manifest
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
                    Path(dirpath) /
                    filename
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
    f"Unique source recordings resolved: "
    f"{len(source_lookup)}"
)


# ------------------------------------------------------------
# 6. Group segments by source recording
# ------------------------------------------------------------

segments_by_file = defaultdict(
    list
)

for row in manifest:

    segments_by_file[
        row["Begin File"].strip()
    ].append(row)


# ------------------------------------------------------------
# 7. Preflight every segment BEFORE writing audio
# ------------------------------------------------------------

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

        if source.getcomptype() != "NONE":

            raise RuntimeError(
                f"Compressed WAV not supported:\n"
                f"{source_path}"
            )

        frames_per_clip = (
            3 * sample_rate
        )

        for row in rows:

            parent_start = decimal_value(
                row,
                "parent_start",
            )

            parent_end = decimal_value(
                row,
                "parent_end",
            )

            if (
                parent_end
                != parent_start + Decimal("3")
            ):

                raise RuntimeError(
                    "Manifest segment is not "
                    "exactly 3 seconds:\n"
                    f"{begin_file} | "
                    f"{parent_start}"
                )

            start_frame = int(
                (
                    parent_start *
                    Decimal(sample_rate)
                ).to_integral_value(
                    rounding=ROUND_HALF_UP
                )
            )

            end_frame = (
                start_frame +
                frames_per_clip
            )

            if end_frame > total_frames:

                raise RuntimeError(
                    "Segment extends beyond source WAV:\n"
                    f"{begin_file} | "
                    f"{parent_start}"
                )


print(
    "All 570 segments passed audio preflight."
)


# ------------------------------------------------------------
# 8. Create new output directories
# ------------------------------------------------------------

REVIEWED_DIR.mkdir(
    parents=True
)

BACKGROUND_DIR.mkdir(
    parents=True
)


# ------------------------------------------------------------
# 9. Extract clips
# ------------------------------------------------------------

qc_rows = []

used_names = set()

source_files = sorted(
    segments_by_file
)


for i, begin_file in enumerate(
    source_files,
    start=1,
):

    rows = segments_by_file[
        begin_file
    ]

    source_path = source_lookup[
        begin_file
    ]

    print(
        f"[{i}/{len(source_files)}] "
        f"{begin_file} "
        f"({len(rows)} segment(s))"
    )

    with wave.open(
        str(source_path),
        "rb",
    ) as source:

        sample_rate = (
            source.getframerate()
        )

        channels = (
            source.getnchannels()
        )

        sample_width = (
            source.getsampwidth()
        )

        frames_per_clip = (
            3 * sample_rate
        )

        for row in rows:

            parent_start = decimal_value(
                row,
                "parent_start",
            )

            parent_end = decimal_value(
                row,
                "parent_end",
            )

            start_frame = int(
                (
                    parent_start *
                    Decimal(sample_rate)
                ).to_integral_value(
                    rounding=ROUND_HALF_UP
                )
            )

            source.setpos(
                start_frame
            )

            audio = source.readframes(
                frames_per_clip
            )

            actual_start = (
                Decimal(start_frame)
                / Decimal(sample_rate)
            )

            alignment_error = (
                actual_start
                - parent_start
            )

            clip_name = (
                f"{Path(begin_file).stem}_"
                f"{decimal_text(parent_start)}s_"
                f"{decimal_text(parent_end)}s.wav"
            )

            if clip_name.lower() in used_names:

                raise RuntimeError(
                    "Duplicate output filename:\n"
                    f"{clip_name}"
                )

            used_names.add(
                clip_name.lower()
            )

            if (
                row["segment_type"]
                == "Background"
            ):

                output_dir = (
                    BACKGROUND_DIR
                )

            elif (
                row["segment_type"]
                == "reviewed"
            ):

                output_dir = (
                    REVIEWED_DIR
                )

            else:

                raise RuntimeError(
                    "Unexpected segment_type: "
                    f"{row['segment_type']}"
                )


            output_path = (
                output_dir /
                clip_name
            )


            with wave.open(
                str(output_path),
                "wb",
            ) as output:

                output.setnchannels(
                    channels
                )

                output.setsampwidth(
                    sample_width
                )

                output.setframerate(
                    sample_rate
                )

                output.writeframes(
                    audio
                )


            qc_rows.append(
                {
                    "segment_type":
                        row["segment_type"],

                    "Begin File":
                        begin_file,

                    "parent_start":
                        decimal_text(
                            parent_start
                        ),

                    "parent_end":
                        decimal_text(
                            parent_end
                        ),

                    "source_audio_path":
                        str(source_path),

                    "sample_rate_hz":
                        sample_rate,

                    "start_frame":
                        start_frame,

                    "actual_start_s":
                        decimal_text(
                            actual_start
                        ),

                    "alignment_error_s":
                        decimal_text(
                            alignment_error
                        ),

                    "frames_written":
                        frames_per_clip,

                    "duration_s":
                        "3",

                    "model_labels":
                        row["model_labels"],

                    "output_path":
                        str(output_path),
                }
            )


# ------------------------------------------------------------
# 10. Final extraction check
# ------------------------------------------------------------

if len(qc_rows) != 570:

    raise RuntimeError(
        f"Expected 570 extracted clips; "
        f"created {len(qc_rows)}."
    )


# ------------------------------------------------------------
# 11. Write extraction QC
# ------------------------------------------------------------

with QC_PATH.open(
    "w",
    newline="",
    encoding="utf-8",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=
            qc_rows[0].keys(),
    )

    writer.writeheader()

    writer.writerows(
        qc_rows
    )


# ------------------------------------------------------------
# 12. Final summary
# ------------------------------------------------------------

print()
print(
    "========== EXTRACTION COMPLETE =========="
)

print(
    f"Reviewed clips:   {reviewed_count}"
)

print(
    f"Background clips: {background_count}"
)

print(
    f"Total extracted:  {len(qc_rows)}"
)

print()

print(
    f"Audio:\n{OUTPUT_ROOT}"
)

print()

print(
    f"Extraction QC:\n{QC_PATH}"
)

print(
    "========================================="
)
