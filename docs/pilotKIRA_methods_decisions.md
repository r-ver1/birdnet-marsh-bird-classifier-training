# Pilot KIRA/RWBL Transfer-Learning Methods and Decision Record

## Purpose

This document records methodological decisions for the pilot BirdNET transfer-learning workflow using King Rail (KIRA) and Red-winged Blackbird (RWBL). 

The pilot currently uses BirdNET v2.4 because it matches the existing few-shot transfer-learning workflow. The annotation and manifest design is intentionally kept model-independent where possible so that the workflow can later be adapted to a stable BirdNET 3.x release.

---

## 1. Source annotations and segment identity

The original Raven annotation CSVs are retained as the source record and are not overwritten by cleanup scripts.

A reviewed three-second parent segment is identified by:

**Begin File + exact File Offset (s)**

Offsets are not rounded or snapped to a three-second grid.

### Rationale

The reviewed segment start is the actual annotation boundary. Diana Johnson's earlier `generate_multihot.py` implementation grouped labeled rows using:

`int(round(start / 3) * 3)`

This shifted some reviewed segments away from their true boundaries. The pilot therefore retains the intended multilabel concept from that workflow but does not retain its rounded window construction.

---

## 2. Completion and review status

For this pilot:

- `Done? = 1` identifies a completed reviewed parent segment.
- `Verify = 1` identifies a confirmed positive focal prediction.
- `Verify = 0` identifies a confirmed negative focal prediction.
- `Done? = 2` identifies a completed background segment.
- Incomplete or unresolved review states are not used as training-ready segments.

Species-specific negatives are not automatically treated as background. A segment can be negative for one focal species while containing another biological class.

---

## 3. Pilot-specific annotation cleanup

The raw annotation files remain unchanged. Cleanup is performed in a derived dataset.

Human-reviewed spelling, formatting, and obvious transcription errors in Common Name values are corrected where the intended identity is unambiguous.

Known environmental or non-training sounds are standardized for exclusion from positive class labels:

- wind, rain, engine, generic environmental sound, and background-noise annotations -> `Noise`
- insect annotations -> `NT`

Two known biological identities that were deliberately not retained as training classes in this pilot were also standardized to `NT`:

- Narrow-mouthed Toad
- Southern Leopard Frog

`Water` is retained as an intentional custom acoustic class because it may help separate water noise from species such as American Bittern.

Cross-version annotation records were used to resolve 13 uncertain events when the exact same acoustic event had a resolved identity in another reviewed version.

Nine events remained genuinely unresolved. These labels were left unchanged rather than being recoded to `NT`.

---

## 4. Whole-segment exclusion for unresolved sounds

If an unresolved sound occurs anywhere within a three-second parent segment, the entire parent segment is excluded from the pilot.

Unresolved labels include:

- `UNK`
- labels ending in `?`, such as `SWSP?` or `COGA?`

The association rule is:

**parent_start <= label_offset < parent_start + 3**

If an unresolved annotation falls within more than one overlapping parent segment, every affected parent is excluded.

### Rationale

An unresolved sound cannot safely be treated as absent from all training classes. Keeping the segment while simply dropping the unresolved annotation could create false-negative labels for a species that is actually present.

For the pilot, 9 unresolved events resulted in 9 excluded `Done? = 1` parent segments.

---

## 5. Training-manifest label reconstruction

### This decision is central to the training design

For every includable `Done? = 1` parent segment, the training manifest will reconstruct the full set of resolved biological labels occurring anywhere within the three-second parent window.

The manifest will not be limited to KIRA and RWBL.

For each parent segment:

1. Use the exact reviewed parent start.
2. Find all cleaned annotations in the same recording with offsets in  
   `parent_start <= label_offset < parent_start + 3`.
3. Retain every resolved biological label for segment membership that maps to a BirdNET v2.4 class.
4. Retain the approved novel class `Water`.
5. Count each class only once per parent segment, regardless of how many annotated calls of that class occur.
6. Ignore non-training labels such as `NT` and `Noise`.
7. Reject the segment if an unresolved label is present; such segments should already have been removed by the cleanup step.

### Rationale

The annotation protocol was designed so that all identifiable biological sounds in a reviewed segment contribute to the pooled training dataset. A segment containing KIRA, RWBL, and another known species should therefore retain all three classes.

This avoids incorrectly treating an incidental species as absent simply because the original focal review was aimed at a different species.

It also preserves BirdNET's existing knowledge rather than training a custom model as though every non-focal class were negative.

---

## 6. Mapping existing species to BirdNET classes

For species already represented in BirdNET v2.4, the model-facing label must use BirdNET's exact canonical class string from the BirdNET v2.4 label file.

For example, the human annotation may use:

- annotation label: `RWBL`
- Common Name: `Red-winged Blackbird`

but the model-facing class must be the exact BirdNET label, such as:

`Agelaius phoeniceus_Red-winged Blackbird`

### Rationale

The few-shot transfer-learning workflow distinguishes existing source classes from novel classes by exact label-string matching. Using only the common name would make an existing BirdNET class appear novel even when BirdNET already contains that species.

The manifest should therefore preserve both:

- the project annotation identity (for auditability), and
- the canonical BirdNET model label (for training).

Every retained biological class must map to exactly one BirdNET v2.4 class. No unmatched biological label will be silently dropped.

`Water` is an intentional exception because it is a novel custom class rather than an existing BirdNET class.

---

## 7. Labels intentionally ignored as positive training classes

The following values contribute no positive class to the manifest:

- `NT`
- `Noise`
- blank Label values
- environmental sounds standardized to `Noise`
- insect annotations standardized to `NT`
- Narrow-mouthed Toad and Southern Leopard Frog annotations standardized to `NT` for this pilot

These values are ignored only as positive class labels.

### Important interpretation

`NT` does **not** mean that every BirdNET species is absent. It contributes no positive class by itself and must not be converted into a universal negative or into Background.

---

## 8. Background segments

`Done? = 2` segments are maintained as a separate Background class/examples.

Background segments are not reconstructed from species-specific negatives.

A species-specific negative remains a reviewed segment that may contain other positive biological classes.

The current source annotations contain 138 unique completed background segments.

---

## 9. Manifest-specific validation before audio extraction

Annotation cleanup, segment eligibility, unresolved-label exclusion, and
Common Name/BirdNET matching were validated upstream in Scripts 00 and 00b.
Script 02 does not repeat those checks.

Instead, Script 02 performs only validation introduced by constructing the
training manifest:

1. Every resolved annotation encountered during manifest construction must
   be assigned to one of three explicit outcomes:
   - retained existing BirdNET class,
   - approved novel class (`Water`), or
   - intentionally ignored label (`NT` or `Noise`).

2. Completed `Done? = 2` background segments must not contain a resolved
   biological class that should be retained as a positive training label.

3. Verified-positive BirdNET predictions (`Verify = 1`) in includable parent
   segments are reconciled against the reconstructed multilabel set so that
   a confirmed species is not accidentally lost during manifest construction.

Audio extraction begins only after these manifest-specific checks pass.

---

## 10. Pilot QC outcomes retained for reproducibility

After cleanup and whole-segment exclusion:

- Raw completed `Done? = 1` parent segments: 450
- Excluded unresolved parent segments: 9
- Pilot-includable `Done? = 1` parent segments: 441
- Background segments: 138

Pilot-eligible focal review counts:

- King Rail: 169 positive, 74 negative
- Red-winged Blackbird: 111 positive, 1 negative

The nine excluded parent segments account exactly for the change from the raw focal counts to these pilot-eligible counts.

---

## 11. Relationship to the earlier Diana Johnson workflow

The earlier workflow correctly aimed to create multilabel training examples by grouping species associated with the same audio window and writing a comma-separated label set.

The pilot retains that multilabel goal but changes the implementation in several consequential ways:

- uses the exact reviewed parent segment rather than a rounded three-second grid;
- reconstructs labels from all resolved biological annotations inside the parent segment rather than relying only on row-level Common Name values;
- explicitly distinguishes ignored labels, unresolved labels, background, and retained biological classes;
- excludes entire parent segments containing unresolved sounds;
- maps existing classes to exact BirdNET v2.4 model labels so source-class knowledge is preserved;
- validates the manifest before extracting audio.

---

## 12. Reproducibility principle

Each workflow script should read saved outputs from prior stages rather than depend on objects remaining in an interactive R session.

A new R session therefore does not require rerunning earlier completed scripts unless their source data, logic, or outputs have changed.

The manifest-building script should read the saved cleaned annotations and includable-parent outputs produced by the pilot cleanup stage.
