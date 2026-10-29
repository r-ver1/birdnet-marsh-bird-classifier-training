# BirdNET Transfer Learning — Training Run Log

## October 22, 2026 — KIRA Pilot: First Successful Training Test

**Purpose:** Verify that the corrected King Rail pilot dataset can pass through Gio Jacuzzi's BirdNET transfer-learning workflow and produce a loadable custom classifier.

### 1. Software and computing environment

- **Workstation:** Birdbrain, Pop!_OS 22.04, NVIDIA RTX 5090.
- **Python:** 3.10.12, isolated virtual environment.
- **TensorFlow:** 2.15.0, CPU execution.
- **Other installed packages:** librosa 0.10.1, resampy 0.4.3, pandas 2.2.2, tqdm 4.67.1.
- **Research repository:** `r-ver1/birdnet-marsh-bird-classifier-training`, main commit `22b69b1`.
- **Training workflow fork:** `r-ver1/few-shot-transfer-learning-bioacoustics`, branch `marsh-bird-workflow`, commit `8737b78`.
- **BirdNET-Analyzer submodule:** commit `1812b5590bc3c7d135b4ba7f6ab775e3dc4b8128`.
- **Backbone:** BirdNET 2.4, pretrained TFLite model for embedding extraction; corresponding TensorFlow SavedModel available for classifier export.

GPU acceleration was not configured. Training and export succeeded on CPU.

### 2. Training data verification

Pilot dataset: `output/gio_training/pilotKIRA/`

- 434 human-reviewed, strongly annotated audio segments.
- 136 background segments.
- **570 total WAVs and annotation records.**
- Verified no missing WAV references, duplicate annotation keys, or blank reviewed labels.
- Original Raven annotation boundaries preserved; corrected segments used rather than the earlier rounded segmentation.

The dataset, annotations, and training outputs remain local and are excluded from GitHub.

### 3. Model preparation

Configuration: `configs/KIRA/pretrain_config.json`

- 22 target classes; `Water` is the only class absent from the pretrained source-label list.
- Five-fold preparation (`k=5`), sample size 10.
- Learning rate 0.001; batch size 10; hidden units 0; planned maximum 50 epochs.
- Training seed 1.
- Four Water examples reserved for testing.

Executed `src/pretrain_configurable.py` successfully. Five training/validation split tables were generated under:

`output/gio_training/KIRA/fewshot/cache/`

**Important:** Generating five splits did not train five models.

### 4. One-epoch CPU smoke test

Trained the first prepared split (`I0`) using Gio's `train_fewshot.py`, with one epoch, four CPU threads, and automatic hyperparameter tuning disabled.

**Measured runtime:** 2 minutes 43 seconds.

- Start: October 22, 2026, 13:57:34 EDT.
- Finish: October 22, 2026, 14:00:17 EDT.
- Training process exit status: 0.
- Reported best AUPRC: 0.0997.
- Reported best AUROC: 0.4865.

These metrics are diagnostic outputs from a one-epoch technical test, **not evidence of KIRA classifier performance**.

The script displayed `Unable to report validation results` after training. This appears related to its optional plotting/reporting step; the underlying exception was not confirmed.

### 5. Export verification

Output directory: `output/gio_training/KIRA/smoke_tests/`

Files produced:

- `KIRA_I0_1epoch.tflite` — approximately 24 MB.
- `KIRA_I0_1epoch_Labels.txt` — 22 labels.
- `KIRA_I0_1epoch_Params.csv`.
- `KIRA_I0_1epoch.log` — approximately 227 KB.

The exported classifier successfully loaded through `tf.lite.Interpreter` and allocated tensors.

- Input shape: `[1, 144000]`.
- Output shape: `[1, 22]`.
- Verified that the output class count equals 22.

**Conclusion:** End-to-end preparation, CPU training, TFLite export, and model loading succeeded. Predictions on evaluation audio and independent performance assessment remain untested.

### 6. Decisions from October 22 meeting with Gio

Gio recommended simplifying the immediate proof of concept:

1. Train a single KIRA model using `k=1`, rather than completing five-fold cross-validation first.
2. Test the segment-level performance evaluation pipeline, potentially using Gio's example data initially:
   `https://github.com/giojacuzzi/few-shot-transfer-learning-bioacoustics/blob/main/src/eval_segment_perf.py`
3. Aim to train and preliminarily evaluate the KIRA pilot by October 29, 2026.
4. Prioritize obtaining a functional KIRA classifier during 2026; refine it if preliminary performance warrants.
5. Tentatively revisit the larger focal marsh-bird classifier project in January 2027.

### 7. Outstanding work as of October 29

- Prepare and train a full `k=1` KIRA model without overwriting existing experimental outputs.
- Test and adapt Gio's performance evaluation workflow for our data and directory structure.
- Establish an appropriate independent KIRA evaluation dataset. The four held-out Water examples do not constitute a KIRA-specific test set.
- Compare the custom KIRA classifier against pretrained BirdNET 2.4.
- Document results, limitations, and subsequent methodological decisions.

**Status: Technical proof of concept successful; full training and performance evaluation pending.**