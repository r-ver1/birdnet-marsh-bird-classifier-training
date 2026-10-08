# ============================================================
# 00b_clean_pilotKIRA_annotations.R
#
# Pilot-specific cleanup decisions for the KIRA/RWBL
# transfer-learning dataset.
#
# IMPORTANT:
#   - The original annotation CSVs are NEVER modified.
#   - Generic QC is performed by 00_preflight_annotation_qc.R.
#   - This script contains HUMAN-APPROVED decisions specific
#     to this pilot annotation batch.
#   - Ambiguous sounds are NOT silently recoded.
#   - If an unresolved sound occurs inside a completed
#     3-second parent segment, the WHOLE parent segment is
#     excluded from this pilot.
# ============================================================

# ---- 1. Run generic preflight and create working copy ----

source("scripts/qc/00_preflight_annotation_qc.R")

clean_annotations <- all_annotations

dir.create(
  "output/qc",
  recursive = TRUE,
  showWarnings = FALSE
)


# ---- 2. Helper functions and cleanup log ----

# Record every approved cleanup rule that is applied.
# This gives us a permanent record without changing the
# original annotation CSVs.

log_rows <- list()

add_log <- function(
    rule_type,
    original_value,
    new_label = NA_character_,
    new_common_name = NA_character_,
    rows_changed = 0,
    decision_reason = NA_character_
) {
  
  log_rows[[length(log_rows) + 1]] <<- data.frame(
    rule_type = rule_type,
    original_value = original_value,
    new_label = new_label,
    new_common_name = new_common_name,
    rows_changed = rows_changed,
    decision_reason = decision_reason,
    stringsAsFactors = FALSE
  )
}


# Compare numeric offsets without depending on printed
# decimal formatting.
same_offset <- function(x, y) {
  abs(x - y) < 1e-7
}


# ---- 3. Correct approved Common Name typos ----
#
# REASONING / DECISION:
# These names were reviewed by the researcher and determined
# to be transcription, spelling, spacing, or capitalization
# errors rather than uncertain biological identifications.
#
# Therefore the Common Name can be corrected to the intended
# BirdNET-compatible Common Name without excluding the segment.
#
# Fuzzy matching is NOT used to make these decisions.
# The fuzzy matches from Script 00 were only review aids.

name_corrections <- c(
  "AmericanBullfrog" = "American Bullfrog",
  "anada Goose" = "Canada Goose",
  "Cananda Goose" = "Canada Goose",
  "Comon Yellowthroat" = "Common Yellowthroat",
  "Northen Cricket Frog" = "Northern Cricket Frog",
  "Pied-billedGrebe" = "Pied-billed Grebe",
  
  "Rd-winged Blackbird" = "Red-winged Blackbird",
  "Red-wined Blackbird" = "Red-winged Blackbird",
  "Red-winge Blackbird" = "Red-winged Blackbird",
  "Red-winged B lackbird" = "Red-winged Blackbird",
  "Red-winged Backbird" = "Red-winged Blackbird",
  "Red-winged Blachbird" = "Red-winged Blackbird",
  "Red-winged Blackbird Conklaree" = "Red-winged Blackbird",
  "Red-winged Blackird" = "Red-winged Blackbird",
  "Red-winged Blakbird" = "Red-winged Blackbird",
  "Red-winged Blakcbird" = "Red-winged Blackbird",
  "Red-wonged Blackbird" = "Red-winged Blackbird",
  "Redw-inged Blackbird" = "Red-winged Blackbird",
  "RWBL" = "Red-winged Blackbird",
  
  "Spring Peeperq" = "Spring Peeper",
  "Vriginia Rail" = "Virginia Rail"
)


common_clean <- gsub(
  "\\s+",
  " ",
  trimws(as.character(clean_annotations$`Common Name`))
)

for (old_name in names(name_corrections)) {
  
  idx <- which(common_clean == old_name)
  
  clean_annotations$`Common Name`[idx] <-
    name_corrections[[old_name]]
  
  add_log(
    rule_type = "Correct Common Name typo",
    original_value = old_name,
    new_common_name = name_corrections[[old_name]],
    rows_changed = length(idx),
    decision_reason =
      "Human-reviewed transcription/spelling error; biological identity was not ambiguous."
  )
}


# ---- 4. Ignore known non-target taxa ----
#
# REASONING / DECISION:
# Narrow-mouthed Toad and Southern Leopard Frog were reviewed
# and deliberately excluded because they are not target classes
# for this project.
#
# Their identities are known, so their presence does NOT make
# the surrounding 3-second segment uncertain.
#
# Only these particular label annotations are changed to NT.
# The parent segment remains eligible if everything else in it
# is usable.

exclude_common_names <- c(
  "Narrow-mouthed Toad",
  "Southern Leopard Frog"
)


common_clean <- gsub(
  "\\s+",
  " ",
  trimws(as.character(clean_annotations$`Common Name`))
)

for (name in exclude_common_names) {
  
  idx <- which(common_clean == name)
  
  clean_annotations$Label[idx] <- "NT"
  
  add_log(
    rule_type = "Known non-target taxon",
    original_value = name,
    new_label = "NT",
    rows_changed = length(idx),
    decision_reason =
      "Species identity known, but taxon is not a target for this project; ignore label without excluding parent segment."
  )
}


# ---- 5. Fill missing Common Names when the label is unambiguous ----
#
# REASONING / DECISION:
# These labels have known meanings. The Common Name was missing,
# but the biological identification itself was not uncertain.
#
# Therefore we can supply the appropriate Common Name rather
# than requiring re-review of the sound.

label_name_map <- c(
  "RWBL" = "Red-winged Blackbird",
  "KIRA" = "King Rail",
  "MAWR" = "Marsh Wren",
  "Northern Cricket Frog" = "Northern Cricket Frog",
  "SOSP" = "Song Sparrow",
  "TRUS" = "Trumpeter Swan"
)


for (lab in names(label_name_map)) {
  
  current_label <- trimws(
    as.character(clean_annotations$Label)
  )
  
  current_name <- trimws(
    as.character(clean_annotations$`Common Name`)
  )
  
  idx <- which(
    current_label == lab &
      (is.na(current_name) | current_name == "")
  )
  
  clean_annotations$`Common Name`[idx] <-
    label_name_map[[lab]]
  
  add_log(
    rule_type = "Fill missing Common Name",
    original_value = lab,
    new_common_name = label_name_map[[lab]],
    rows_changed = length(idx),
    decision_reason =
      "Label identity was unambiguous; missing Common Name supplied from researcher-approved label meaning."
  )
}


# ---- 6. Standardize Water as an approved novel class ----
#
# REASONING / DECISION:
# Water is intentionally retained as a NOVEL acoustic class.
# It is useful for distinguishing water sounds from American
# Bittern and is not intended to match a BirdNET species.
#
# Both 'water' and 'Water' are standardized to 'Water'.

current_label <- trimws(
  as.character(clean_annotations$Label)
)

water_idx <- which(
  tolower(current_label) == "water"
)

clean_annotations$Label[water_idx] <- "Water"

current_name <- trimws(
  as.character(clean_annotations$`Common Name`)
)

missing_water_name <- water_idx[
  is.na(current_name[water_idx]) |
    current_name[water_idx] == ""
]

clean_annotations$`Common Name`[
  missing_water_name
] <- "Water"

add_log(
  rule_type = "Standardize approved novel class",
  original_value = "water / Water",
  new_label = "Water",
  new_common_name = "Water",
  rows_changed = length(water_idx),
  decision_reason =
    "Researcher-approved novel class retained to distinguish water sounds from American Bittern."
)


# ---- 7. Ignore known environmental/noise sounds ----
#
# REASONING / DECISION:
# Wind, engine noise, rain, generic environmental sound, and
# Background Noise are known non-biological sounds.
#
# Because their identity is known, they can safely be treated
# as Noise. They do NOT make the parent segment ambiguous.

noise_labels <- c(
  "wind",
  "Engine",
  "rain",
  "Environmental",
  "Background Noise"
)


for (lab in noise_labels) {
  
  current_label <- trimws(
    as.character(clean_annotations$Label)
  )
  
  idx <- which(current_label == lab)
  
  clean_annotations$Label[idx] <- "Noise"
  
  add_log(
    rule_type = "Known environmental sound",
    original_value = lab,
    new_label = "Noise",
    rows_changed = length(idx),
    decision_reason =
      "Known environmental/non-biological sound; intentionally ignored without excluding parent segment."
  )
}


# ---- 8. Ignore known insect sounds ----
#
# REASONING / DECISION:
# Insect sounds are not target classes for this project.
#
# Their identity is sufficiently known to ignore them as NT.
# They therefore do NOT cause exclusion of the parent segment.

insect_labels <- c(
  "Insect",
  "insect"
)


for (lab in insect_labels) {
  
  current_label <- trimws(
    as.character(clean_annotations$Label)
  )
  
  idx <- which(current_label == lab)
  
  clean_annotations$Label[idx] <- "NT"
  
  add_log(
    rule_type = "Known non-target sound",
    original_value = lab,
    new_label = "NT",
    rows_changed = length(idx),
    decision_reason =
      "Known insect sound; not a target class and intentionally ignored."
  )
}


# ---- 9. Resolve uncertain labels using other annotation versions ----
#
# REASONING / DECISION:
# Before asking for new manual listening, the researcher checked
# the same recording + exact File Offset across all available
# annotation-file versions.
#
# These events had an uncertain annotation in one version but a
# definitive annotation at the SAME acoustic event in another
# version.
#
# Because a previous human review already resolved the identity,
# these exact events can be corrected without listening again.
#
# These are EVENT-SPECIFIC corrections, not general rules.

event_resolutions <- data.frame(
  begin_file = c(
    "MINI06_20250410_050000.wav",
    "MINI06_20250410_050000.wav",
    "MINI06_20250513_080002.wav",
    "SMA06000_20250402_193800.wav",
    "SMA06000_20250502_201100.wav",
    "SMA06000_20250502_201100.wav",
    "SMA06024_20250327_193200.wav",
    "SMA06024_20250327_193200.wav",
    "SMA06024_20250407_194400.wav",
    "SMA06024_20250407_194400.wav",
    "SMA06024_20250602_204000.wav",
    "SMA06024_20250602_204000.wav",
    "SMA06024_20250602_204000.wav"
  ),
  
  file_offset_s = c(
    229.0230,
    322.6413,
    2453.4001,
    343.3289,
    1152.0507,
    1154.4961,
    693.8367,
    695.2305,
    1278.4006,
    1279.6602,
    1253.2230,
    2181.4044,
    2182.7758
  ),
  
  old_label = c(
    "COGA?",
    "UNK",
    "UNK",
    "UNK",
    "UNK",
    "UNK",
    "SWSP??",
    "SWSP??",
    "SWSP?",
    "SWSP?",
    "UNK",
    "UNK",
    "UNK"
  ),
  
  new_label = c(
    "COGA",
    "COGA",
    "Noise",
    "RWBL",
    "NT",
    "NT",
    "NT",
    "NT",
    "NT",
    "NT",
    "NT",
    "MAWR",
    "MAWR"
  ),
  
  new_common_name = c(
    "Common Gallinule",
    "Common Gallinule",
    NA,
    "Red-winged Blackbird",
    NA,
    NA,
    NA,
    NA,
    NA,
    NA,
    NA,
    "Marsh Wren",
    "Marsh Wren"
  ),
  
  stringsAsFactors = FALSE
)


for (i in seq_len(nrow(event_resolutions))) {
  
  r <- event_resolutions[i, ]
  
  idx <- which(
    clean_annotations$`Begin File` == r$begin_file &
      same_offset(
        clean_annotations$offset_num,
        r$file_offset_s
      ) &
      trimws(as.character(clean_annotations$Label)) ==
      r$old_label
  )
  
  # These are hard-coded, human-reviewed event resolutions.
  # If one cannot be found, stop rather than silently continuing.
  if (length(idx) == 0) {
    
    stop(
      paste(
        "Expected cross-version resolution event not found:",
        r$begin_file,
        r$file_offset_s,
        r$old_label
      )
    )
  }
  
  clean_annotations$Label[idx] <- r$new_label
  
  if (!is.na(r$new_common_name)) {
    
    clean_annotations$`Common Name`[idx] <-
      r$new_common_name
  }
  
  add_log(
    rule_type =
      "Resolved from another annotation version",
    
    original_value = paste(
      r$begin_file,
      r$file_offset_s,
      r$old_label,
      sep = " | "
    ),
    
    new_label = r$new_label,
    new_common_name = r$new_common_name,
    rows_changed = length(idx),
    
    decision_reason =
      "Same acoustic event had a definitive human-reviewed label in another annotation-file version."
  )
}


# ---- 10. Define unresolved events WITHOUT changing them ----
#
# REASONING / DECISION:
# After checking all annotation versions, these events still
# could not be resolved confidently.
#
# For this pilot we are NOT spending additional time listening
# to them.
#
# CRITICAL:
#   UNK remains UNK.
#   SWSP? remains SWSP?.
#   COGA? remains COGA?.
#
# We do NOT convert an unresolved sound to NT.
#
# Instead, every completed 3-second parent segment containing
# one of these events is excluded from the pilot entirely.
#
# This prevents an unknown sound from being treated as if it
# were confidently absent or irrelevant.

unresolved_events <- data.frame(
  begin_file = c(
    "2MA04668_20250519_202700.wav",
    "2MA06246_20250406_064700.wav",
    "2MA06246_20250424_200200.wav",
    "2MA06246_20250507_201600.wav",
    "MINI06_20250410_050000.wav",
    "SMA06001_20250528_203600.wav",
    "SMA06024_20250326_193100.wav",
    "SMA06024_20250327_193200.wav",
    "SMA06024_20250402_193800.wav"
  ),
  
  file_offset_s = c(
    1894.8876,
    1936.2317,
    415.9579,
    2237.2560,
    33.3075,
    714.9024,
    28.3807,
    696.3261,
    83.0977
  ),
  
  label = c(
    "UNK",
    "UNK",
    "UNK",
    "UNK",
    "UNK",
    "UNK",
    "SWSP?",
    "SWSP?",
    "COGA?"
  ),
  
  stringsAsFactors = FALSE
)


# Confirm that each unresolved event still exists unchanged
# in the cleaned working annotations.

for (i in seq_len(nrow(unresolved_events))) {
  
  r <- unresolved_events[i, ]
  
  idx <- which(
    clean_annotations$`Begin File` == r$begin_file &
      same_offset(
        clean_annotations$offset_num,
        r$file_offset_s
      ) &
      trimws(as.character(clean_annotations$Label)) ==
      r$label
  )
  
  if (length(idx) == 0) {
    
    stop(
      paste(
        "Unresolved event was unexpectedly changed or missing:",
        r$begin_file,
        r$file_offset_s,
        r$label
      )
    )
  }
}


# ---- 11. Identify every parent segment containing an unresolved event ----
#
# REASONING / DECISION:
# Segment eligibility is determined at the 3-second parent level.
#
# A label belongs to a parent segment when:
#
#   label offset >= parent start
#   label offset <  parent start + 3
#
# If an unresolved event falls into more than one overlapping
# parent window, ALL affected parent segments are excluded.

unresolved_parent_map <- list()


for (i in seq_len(nrow(unresolved_events))) {
  
  r <- unresolved_events[i, ]
  
  hits <- done1_parents[
    done1_parents$`Begin File` == r$begin_file &
      r$file_offset_s >= done1_parents$parent_start &
      r$file_offset_s < done1_parents$parent_start + 3,
  ]
  
  if (nrow(hits) == 0) {
    
    stop(
      paste(
        "Unresolved event did not map to a Done = 1 parent:",
        r$begin_file,
        r$file_offset_s,
        r$label
      )
    )
  }
  
  unresolved_parent_map[[length(unresolved_parent_map) + 1]] <- data.frame(
    `Begin File` = hits$`Begin File`,
    parent_start = hits$parent_start,
    trigger_offset = r$file_offset_s,
    trigger_label = r$label,
    reason =
      "Contains unresolved acoustic label; whole parent excluded from pilot",
    check.names = FALSE
  )
}


unresolved_parent_map <- do.call(
  rbind,
  unresolved_parent_map
)


# Unique parent segments to exclude.

excluded_parent_segments <- unique(
  unresolved_parent_map[
    ,
    c(
      "Begin File",
      "parent_start"
    )
  ]
)

excluded_parent_segments$reason <-
  "Contains unresolved acoustic label; whole parent excluded from pilot"


# ---- 12. Define includable Done = 1 parent segments ----
#
# REASONING / DECISION:
# Parent-segment identity is:
#
#   Begin File + exact parent start
#
# The excluded parents were copied directly from done1_parents,
# so we match on those two fields directly.
#
# We do NOT convert numeric offsets to text for matching.

excluded_lookup <- unique(
  excluded_parent_segments[
    ,
    c(
      "Begin File",
      "parent_start"
    )
  ]
)

excluded_lookup$exclude_from_pilot <- TRUE


# Join the exclusion flag back onto every completed parent.
parent_status <- merge(
  done1_parents[
    ,
    c(
      "Begin File",
      "parent_start"
    )
  ],
  excluded_lookup,
  by = c(
    "Begin File",
    "parent_start"
  ),
  all.x = TRUE,
  sort = FALSE
)


# Parents not found in the exclusion table remain eligible.
parent_status$exclude_from_pilot[
  is.na(parent_status$exclude_from_pilot)
] <- FALSE


# Safety check:
# every parent we intended to exclude must actually have matched.
if (
  sum(parent_status$exclude_from_pilot) !=
  nrow(excluded_lookup)
) {
  
  stop(
    "Not all excluded parent segments matched the Done = 1 parent table."
  )
}


# These are the completed parent segments eligible for the pilot.
includable_done1_parents <- parent_status[
  !parent_status$exclude_from_pilot,
  c(
    "Begin File",
    "parent_start"
  )
]
# ---- 13. Validate that no ambiguous labels remain in includable parents ----
#
# REASONING:
# It is not enough to make our known list of nine exclusions.
# We also verify that NO remaining includable parent contains
# UNK or a question-mark label.
#
# If one is found, the script stops rather than silently
# allowing that segment into training.

clean_annotations$label_clean <- trimws(
  as.character(clean_annotations$Label)
)

ambiguous_rows <- clean_annotations[
  clean_annotations$label_clean == "UNK" |
    grepl(
      "\\?$",
      clean_annotations$label_clean
    ),
]


ambiguous_in_included <- list()


if (nrow(ambiguous_rows) > 0) {
  
  for (i in seq_len(nrow(ambiguous_rows))) {
    
    file_i <- ambiguous_rows$`Begin File`[i]
    start_i <- ambiguous_rows$offset_num[i]
    
    if (is.na(file_i) || is.na(start_i)) {
      next
    }
    
    hits <- includable_done1_parents[
      includable_done1_parents$`Begin File` == file_i &
        start_i >= includable_done1_parents$parent_start &
        start_i < includable_done1_parents$parent_start + 3,
    ]
    
    if (nrow(hits) > 0) {
      
      ambiguous_in_included[[length(ambiguous_in_included) + 1]] <- data.frame(
        `Begin File` = file_i,
        label_offset = start_i,
        Label = ambiguous_rows$label_clean[i],
        parent_start = hits$parent_start,
        check.names = FALSE
      )
    }
  }
}


if (length(ambiguous_in_included) > 0) {
  
  ambiguous_in_included <- unique(
    do.call(
      rbind,
      ambiguous_in_included
    )
  )
  
  write.csv(
    ambiguous_in_included,
    "output/qc/00b_ERROR_ambiguous_labels_in_included_segments.csv",
    row.names = FALSE
  )
  
  stop(
    "Ambiguous labels remain inside includable parent segments."
  )
}


# ---- 14. Validate retained labels have usable Common Names ----
#
# REASONING:
# Any biological or novel class retained in an includable
# training segment must have a usable Common Name.
#
# NT and Noise are intentionally ignored and therefore do not
# require Common Names.

retained_rows <- clean_annotations[
  !is.na(clean_annotations$label_clean) &
    clean_annotations$label_clean != "" &
    !toupper(clean_annotations$label_clean) %in%
    c("NT", "NOISE"),
]


retained_rows$in_includable_parent <- FALSE


for (i in seq_len(nrow(retained_rows))) {
  
  file_i <- retained_rows$`Begin File`[i]
  start_i <- retained_rows$offset_num[i]
  
  if (is.na(file_i) || is.na(start_i)) {
    next
  }
  
  parents_i <- includable_done1_parents[
    includable_done1_parents$`Begin File` == file_i,
  ]
  
  retained_rows$in_includable_parent[i] <- any(
    start_i >= parents_i$parent_start &
      start_i < parents_i$parent_start + 3
  )
}


retained_rows <- retained_rows[
  retained_rows$in_includable_parent,
]


retained_common_name <- gsub(
  "\\s+",
  " ",
  trimws(
    as.character(
      retained_rows$`Common Name`
    )
  )
)


missing_retained_name <- retained_rows[
  is.na(retained_common_name) |
    retained_common_name == "",
]


if (nrow(missing_retained_name) > 0) {
  
  write.csv(
    missing_retained_name,
    "output/qc/00b_ERROR_missing_names_in_included_segments.csv",
    row.names = FALSE
  )
  
  stop(
    "Retained labels with missing Common Names remain in includable segments."
  )
}


# ---- 15. Validate retained Common Names against BirdNET or Water ----
#
# REASONING:
# All retained biological labels should map to BirdNET's
# canonical Common Names.
#
# Water is the one researcher-approved novel class for this
# annotation set.

retained_match <- tolower(
  retained_common_name
)

valid_match <- c(
  tolower(birdnet_common_names),
  tolower(novel_classes)
)

bad_name <- !retained_match %in% valid_match


if (any(bad_name)) {
  
  unmatched_retained <- unique(
    retained_common_name[bad_name]
  )
  
  write.csv(
    data.frame(
      unmatched_common_name =
        unmatched_retained
    ),
    "output/qc/00b_ERROR_unmatched_names_in_included_segments.csv",
    row.names = FALSE
  )
  
  stop(
    "Retained Common Names remain unmatched to BirdNET or approved novel classes."
  )
}


# ---- 16. Save cleanup records ----

applied_log <- do.call(
  rbind,
  log_rows
)


write.csv(
  applied_log,
  "output/qc/00b_applied_cleanup_rules.csv",
  row.names = FALSE
)


# Nine unresolved acoustic events remain unchanged here.

write.csv(
  unresolved_events,
  "output/qc/00b_unresolved_events.csv",
  row.names = FALSE
)


# Shows exactly which unresolved event caused which
# parent segment to be excluded.

write.csv(
  unresolved_parent_map,
  "output/qc/00b_unresolved_event_parent_map.csv",
  row.names = FALSE
)


# Unique parent segments excluded from the pilot.

write.csv(
  excluded_parent_segments[
    ,
    c(
      "Begin File",
      "parent_start",
      "reason"
    )
  ],
  "output/qc/00b_excluded_parent_segments.csv",
  row.names = FALSE
)


# Explicit list of parent segments that remain eligible.

write.csv(
  includable_done1_parents,
  "output/qc/00b_includable_done1_parent_segments.csv",
  row.names = FALSE
)


# RDS preserves the exact numeric offsets for downstream R
# scripts and avoids relying on CSV numeric formatting.

saveRDS(
  includable_done1_parents,
  "output/qc/00b_includable_done1_parent_segments.rds"
)


saveRDS(
  clean_annotations,
  "output/qc/00b_pilot_annotations_cleaned.rds"
)


# ---- 17. Final summary ----

cat(
  "\n================ 00b CLEANUP SUMMARY ================\n"
)

cat(
  "Cross-version uncertain events resolved:",
  nrow(event_resolutions),
  "\n"
)

cat(
  "Unresolved events left unchanged:",
  nrow(unresolved_events),
  "\n"
)

cat(
  "Unique Done = 1 parent segments excluded:",
  nrow(excluded_parent_segments),
  "\n"
)

cat(
  "Includable Done = 1 parent segments:",
  nrow(includable_done1_parents),
  "\n"
)

cat(
  "Ambiguous labels inside includable segments: 0\n"
)

cat(
  "Retained labels missing Common Names: 0\n"
)

cat(
  "Retained Common Names unmatched to BirdNET/Water: 0\n"
)

cat(
  "\nCleaned annotations:\n",
  "output/qc/00b_pilot_annotations_cleaned.rds\n"
)

cat(
  "\nIncludable parent segments:\n",
  "output/qc/00b_includable_done1_parent_segments.rds\n"
)

cat(
  "=====================================================\n"
)