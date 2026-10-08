# ============================================================
# 04_prepare_gio_training_inputs.py
#
# Prepare the verified pilot WAVs in the directory structure
# expected by Gio Jacuzzi's few-shot training workflow.
#
# INPUT:
#   output/training_segments/pilotKIRA/
#
# OUTPUT:
#   output/gio_training/pilotKIRA/
#       audio/
#           <434 reviewed WAVs>
#           Background/
#               <136 background WAVs>
#       training_data_annotations.csv
#
# Diana's files and Gio's repository are NOT modified.
# ============================================================

import csv
import shutil
from pathlib import Path


# ------------------------------------------------------------
# 1. Paths
# ------------------------------------------------------------

SOURCE_ROOT = Path(
    "output/training_segments/pilotKIRA"
)

QC_PATH = (
    SOURCE_ROOT /
    "03_extraction_qc.csv"
)

OUTPUT_ROOT = Path(
    "output/gio_training/pilotKIRA"
)

AUDIO_DIR = (
    OUTPUT_ROOT /
    "audio"
)

BACKGROUND_DIR = (
    AUDIO_DIR /
    "Background"
)

ANNOTATION_PATH = (
    OUTPUT_ROOT /
    "training_data_annotations.csv"
)


# ------------------------------------------------------------
# 2. Protect against mixing runs
# ------------------------------------------------------------

if OUTPUT_ROOT.exists():

    raise RuntimeError(
        f"Output directory already exists:\n"
        f"{OUTPUT_ROOT}\n\n"
        "Rename or remove it before rerunning Script 04."
    )


# ------------------------------------------------------------
# 3. Read verified extraction QC
# ------------------------------------------------------------

with QC_PATH.open(
    "r",
    newline="",
    encoding="utf-8-sig",
) as f:

    qc = list(
        csv.DictReader(f)
    )


if len(qc) != 570:

    raise RuntimeError(
        f"Expected 570 extraction-QC rows; "
        f"found {len(qc)}."
    )


reviewed = [
    row
    for row in qc
    if row["segment_type"] == "reviewed"
]

background = [
    row
    for row in qc
    if row["segment_type"] == "Background"
]


if len(reviewed) != 434:

    raise RuntimeError(
        f"Expected 434 reviewed rows; "
        f"found {len(reviewed)}."
    )


if len(background) != 136:

    raise RuntimeError(
        f"Expected 136 Background rows; "
        f"found {len(background)}."
    )


# ------------------------------------------------------------
# 4. Create clean Gio-style directories
# ------------------------------------------------------------

BACKGROUND_DIR.mkdir(
    parents=True
)


# ------------------------------------------------------------
# 5. Copy WAVs and build annotation records
# ------------------------------------------------------------

annotation_rows = []


for row in qc:

    source_path = Path(
        row["output_path"]
    )

    if not source_path.exists():

        raise RuntimeError(
            f"Source clip does not exist:\n"
            f"{source_path}"
        )


    if row["segment_type"] == "reviewed":

        labels = (
            row["model_labels"].strip()
        )

        if not labels:

            raise RuntimeError(
                "Reviewed clip has blank labels:\n"
                f"{source_path}"
            )

        destination = (
            AUDIO_DIR /
            source_path.name
        )

        audio_subdir = "audio"


    elif row["segment_type"] == "Background":

        destination = (
            BACKGROUND_DIR /
            source_path.name
        )

        audio_subdir = "Background"

        # Gio's pretraining code assigns Background
        # from the directory name.
        labels = ""


    else:

        raise RuntimeError(
            "Unexpected segment_type: "
            f"{row['segment_type']}"
        )


    shutil.copy2(
        source_path,
        destination
    )


    annotation_rows.append(
        {
            "audio_subdir":
                audio_subdir,

            # Gio appends ".wav" later,
            # so store only the filename stem.
            "file":
                source_path.stem,

            "labels":
                labels,
        }
    )


# ------------------------------------------------------------
# 6. Write Gio-format annotation CSV
# ------------------------------------------------------------

with ANNOTATION_PATH.open(
    "w",
    newline="",
    encoding="utf-8",
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=[
            "audio_subdir",
            "file",
            "labels",
        ],
    )

    writer.writeheader()

    writer.writerows(
        annotation_rows
    )


# ------------------------------------------------------------
# 7. Verify copied files
# ------------------------------------------------------------

reviewed_wavs = list(
    AUDIO_DIR.glob("*.wav")
)

background_wavs = list(
    BACKGROUND_DIR.glob("*.wav")
)


if len(reviewed_wavs) != 434:

    raise RuntimeError(
        f"Expected 434 reviewed WAVs; "
        f"found {len(reviewed_wavs)}."
    )


if len(background_wavs) != 136:

    raise RuntimeError(
        f"Expected 136 Background WAVs; "
        f"found {len(background_wavs)}."
    )


if len(annotation_rows) != 570:

    raise RuntimeError(
        "Expected 570 annotation rows."
    )


# ------------------------------------------------------------
# 8. Final summary
# ------------------------------------------------------------

print()
print(
    "========== GIO INPUTS PREPARED =========="
)

print(
    f"Reviewed WAVs:   {len(reviewed_wavs)}"
)

print(
    f"Background WAVs: {len(background_wavs)}"
)

print(
    f"Annotation rows: {len(annotation_rows)}"
)

print()

print(
    f"Training package:\n"
    f"{OUTPUT_ROOT}"
)

print()

print(
    f"Annotations:\n"
    f"{ANNOTATION_PATH}"
)

print(
    "========================================="
)
