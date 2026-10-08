# Upstream QC fixes for KIRA/RWBL training set

**Purpose:** Preserve lessons and adjudications discovered while debugging the KIRA/RWBL pilot without changing the current QC scripts now. Revisit these before building an expanded secretive marsh bird training set.

## Event-specific decisions

1. **Virginia Rail false positive**
   - Recording: `SMA06000_20250326_193100.wav`
   - Parent: `381-384 s`
   - Issue: historical copies of the BirdNET Virginia Rail prediction at 381 s had conflicting `Verify` values even though the segment was independently labeled RWBL.
   - Researcher adjudication: Virginia Rail is **not present**.
   - Future upstream action: normalize that Virginia Rail prediction to `Verify = 0` across historical copies.

2. **MAWR / Common Name contradiction**
   - Recording: `SMA06000_20250704_054400.wav`
   - Parent: `420-423 s`
   - Problem row: offset `420.0317 s`, `Label = MAWR`, but `Common Name = Swamp Sparrow`.
   - Independent annotations establish both Marsh Wren and Swamp Sparrow elsewhere in the parent.
   - Future upstream action: remove/correct the contradictory Common Name on this MAWR row while retaining `Label = MAWR`.

3. **Unresolved SWSP parents: exclude whole parents**
   - Recording: `SMA06024_20250408_194500.wav`
   - Parent starts: `1110`, `1137`, `1140 s`
   - Issue: unresolved / conflicting Swamp Sparrow status across historical annotation versions (`Verify = U`, conflicting review states, and/or `Done? = 0.5`).
   - Future upstream action: flag and exclude these complete 3-second parents unless they are later manually adjudicated.

4. **Unresolved KIRA/VIRA parent: exclude whole parent**
   - Recording: `SMA06024_20250617_040000.wav`
   - Parent: `822-825 s`
   - King Rail is independently established, but Virginia Rail status conflicts across historical copies.
   - Future upstream action: exclude the whole parent unless VIRA presence/absence is manually resolved.

5. **Annotation typo**
   - Recording: `SMA06024_20250329_040000.wav`
   - Offset: `58.9416 s`
   - `Backgrond Noise` -> `Background Noise`
   - Future upstream action: typo/normalization QC should catch this before manifest construction.

## Generic QC improvements to add for expanded dataset

- Detect the **same BirdNET prediction across historical versions with conflicting `Verify` values**.
- Flag any candidate parent containing **`Verify = U`**.
- Flag **`Done? = 0.5`** in any historical copy of an otherwise eligible parent.
- Flag manual rows where **`Label` and nonblank `Common Name` contradict each other**.
- Compare BirdNET Common Names **case-insensitively**, but write canonical BirdNET capitalization downstream.
- Treat non-positive labels (`NT`, `Noise`, `Background Noise`, etc.) **case-insensitively**.
- Systematically flag unexpected label spellings/typos rather than accumulating one-off exceptions in the manifest script.
- Preserve all resolved biological labels that map to BirdNET classes; do not silently drop incidental non-focal species.
- Continue excluding an entire parent when an unresolved sound remains anywhere within the 3-second parent.

## KIRA set checkpoint

The current KIRA manifest was successfully produced without revising the earlier QC scripts:
- Reviewed `Done = 1`: **437**
- Clean `Done = 2` backgrounds: **137**
- Total manifest segments: **574**
- Reviewed segments with zero retained positive classes: **3**

Background rule retained for future work:
**training background should contain no labeled biological sounds.** A single `Done = 2` segment containing Green Frog + Song Sparrow was excluded from training use rather than redefining background.

