# ============================================================
# 03b_verify_pilot_extraction.py
#
# Verify the completed Script 03 audio extraction.
#
# This script does NOT modify any files.
# ============================================================

import csv
import wave
from pathlib import Path


OUTPUT_ROOT = Path(
    "output/training_segments/pilotKIRA"
)

REVIEWED_DIR = OUTPUT_ROOT / "reviewed"
BACKGROUND_DIR = OUTPUT_ROOT / "background"

QC_PATH = (
    OUTPUT_ROOT /
    "03_extraction_qc.csv"
)


# ---- 1. Count extracted WAV files ----

reviewed_files = list(
    REVIEWED_DIR.glob("*.wav")
)

background_files = list(
    BACKGROUND_DIR.glob("*.wav")
)

all_files = (
    reviewed_files +
    background_files
)


print(
    f"Reviewed WAVs:   {len(reviewed_files)}"
)

print(
    f"Background WAVs: {len(background_files)}"
)

print(
    f"Total WAVs:      {len(all_files)}"
)


if len(reviewed_files) != 434:
    raise RuntimeError(
        "Expected 434 reviewed WAVs."
    )

if len(background_files) != 136:
    raise RuntimeError(
        "Expected 136 Background WAVs."
    )

if len(all_files) != 570:
    raise RuntimeError(
        "Expected 570 total WAVs."
    )


# ---- 2. Check every WAV is exactly 3 seconds ----

bad_durations = []


for path in all_files:

    with wave.open(
        str(path),
        "rb",
    ) as audio:

        sample_rate = (
            audio.getframerate()
        )

        frames = (
            audio.getnframes()
        )

        expected_frames = (
            3 * sample_rate
        )

        if frames != expected_frames:

            bad_durations.append(
                (
                    path,
                    frames,
                    sample_rate,
                )
            )


if bad_durations:

    for item in bad_durations:
        print(item)

    raise RuntimeError(
        "One or more WAVs are not exactly 3 seconds."
    )


print(
    "All WAVs are exactly 3.000 seconds."
)


# ---- 3. Read extraction QC ----

with QC_PATH.open(
    "r",
    newline="",
    encoding="utf-8-sig",
) as f:

    qc = list(
        csv.DictReader(f)
    )


print(
    f"QC rows:         {len(qc)}"
)


if len(qc) != 570:
    raise RuntimeError(
        "Expected 570 QC rows."
    )


# ---- 4. Confirm every QC output exists ----

missing_outputs = [
    row["output_path"]
    for row in qc
    if not Path(
        row["output_path"]
    ).exists()
]


if missing_outputs:

    print(
        "\nMissing output files:"
    )

    for path in missing_outputs:
        print(path)

    raise RuntimeError(
        "QC references missing WAV files."
    )


print(
    "Every QC output path exists."
)


# ---- 5. Check sample-alignment errors ----

alignment_errors = [
    abs(
        float(
            row["alignment_error_s"]
        )
    )
    for row in qc
]


max_error = max(
    alignment_errors
)


print(
    "Maximum absolute start alignment error: "
    f"{max_error:.9f} s"
)


# Each start should be no farther than half
# one sample from the manifest start.

for row in qc:

    sample_rate = float(
        row["sample_rate_hz"]
    )

    error = abs(
        float(
            row["alignment_error_s"]
        )
    )

    half_sample = (
        0.5 / sample_rate
    )

    # Tiny tolerance for decimal/string conversion.
    if error > (
        half_sample + 1e-9
    ):

        raise RuntimeError(
            "Start alignment exceeds half a sample:\n"
            f"{row['Begin File']} | "
            f"{row['parent_start']}"
        )


print(
    "All starts are aligned to the nearest audio sample."
)


# ---- 6. Confirm label expectations ----

for row in qc:

    labels = row[
        "model_labels"
    ].strip()

    if (
        row["segment_type"]
        == "reviewed"
        and labels == ""
    ):

        raise RuntimeError(
            "Reviewed clip has blank labels."
        )

    if (
        row["segment_type"]
        == "Background"
        and labels != ""
    ):

        raise RuntimeError(
            "Background clip unexpectedly has labels."
        )


print(
    "Reviewed/Background label checks passed."
)


# ---- 7. Final result ----

print()
print(
    "========== EXTRACTION VERIFIED =========="
)

print(
    "434 reviewed WAVs"
)

print(
    "136 Background WAVs"
)

print(
    "570 total WAVs"
)

print(
    "570 QC rows"
)

print(
    "All WAVs exactly 3.000 seconds"
)

print(
    "All sample alignments valid"
)

print(
    "All label checks passed"
)

print(
    "========================================="
)
