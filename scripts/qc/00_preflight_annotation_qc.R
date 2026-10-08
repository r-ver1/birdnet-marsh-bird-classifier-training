# ============================================================
# 00_preflight_annotation_qc.R
#
# Preflight QC for source annotation files.
#
# Checks:
#   1. Required columns
#   2. Unique label events inside completed Done? = 1 segments
#   3. Missing Common Names that matter for training
#   4. Common Name consistency with BirdNET v2.4
#   5. Fuzzy suggestions for unmatched names
#
# Original annotation CSVs are NEVER changed.
# ============================================================


# ---- 1. Set paths and required columns ----

dir.create("output/qc", recursive = TRUE, showWarnings = FALSE)

birdnet_label_file <- "D:/BirdNET_GLOBAL_6K_V2.4_Labels.txt"

required_columns <- c(
  "Begin File",
  "File Offset (s)",
  "Common Name",
  "Species Code",
  "Label",
  "Verify",
  "Done?"
)


# ---- 2. Find original annotation files ----

ann_files <- list.files(
  "annotation_files",
  pattern = "\\.csv$",
  full.names = TRUE
)

bg_files <- list.files(
  "bg_annotation_files",
  pattern = "\\.csv$",
  full.names = TRUE
)

# Exclude DJ's derived combined files.
source_files <- c(
  ann_files[basename(ann_files) != "combined_annotations.csv"],
  bg_files[basename(bg_files) != "combined_annotations.csv"]
)

cat("Source annotation files:", length(source_files), "\n")

if (length(source_files) == 0) {
  stop("No source annotation files found.")
}


# ---- 3. Check required columns ----

column_check <- do.call(
  rbind,
  lapply(source_files, function(f) {
    
    cols <- names(
      read.csv(f, nrows = 0, check.names = FALSE)
    )
    
    missing <- setdiff(required_columns, cols)
    
    data.frame(
      source_file = basename(f),
      missing_columns = paste(missing, collapse = "; "),
      passed = length(missing) == 0
    )
  })
)

print(column_check, row.names = FALSE)

if (!all(column_check$passed)) {
  stop("One or more files are missing required columns.")
}


# ---- 4. Read all source annotations ----

all_annotations <- do.call(
  rbind,
  lapply(source_files, function(f) {
    
    x <- read.csv(
      f,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    
    x$source_file <- basename(f)
    x
  })
)

cat("Annotation rows read:", nrow(all_annotations), "\n")


# ---- 5. Prepare fields used for QC ----

all_annotations$label_clean <- trimws(
  as.character(all_annotations$Label)
)

all_annotations$done_num <- suppressWarnings(
  as.numeric(all_annotations$`Done?`)
)

all_annotations$offset_num <- suppressWarnings(
  as.numeric(all_annotations$`File Offset (s)`)
)

# Keep meaningful annotation labels.
# NT and noise are ignored.
label_rows <- all_annotations[
  !is.na(all_annotations$label_clean) &
    all_annotations$label_clean != "" &
    !toupper(all_annotations$label_clean) %in% c("NT", "NOISE"),
]


# ---- 6. Keep labels inside Done? = 1 parent segments ----

# Each completed parent segment begins at its exact File Offset
# and spans 3 seconds.

done1_parents <- unique(
  all_annotations[
    which(
      all_annotations$done_num == 1 &
        !is.na(all_annotations$offset_num)
    ),
    c("Begin File", "offset_num")
  ]
)

names(done1_parents)[2] <- "parent_start"


# Determine whether each label falls inside any completed
# 3-second parent segment from the same recording.

label_rows$in_done1_parent <- FALSE

for (i in seq_len(nrow(label_rows))) {
  
  file_i <- label_rows$`Begin File`[i]
  label_start <- label_rows$offset_num[i]
  
  if (is.na(file_i) || is.na(label_start)) {
    next
  }
  
  parent_starts <- done1_parents$parent_start[
    done1_parents$`Begin File` == file_i
  ]
  
  label_rows$in_done1_parent[i] <- any(
    label_start >= parent_starts &
      label_start < parent_starts + 3
  )
}

label_rows <- label_rows[
  label_rows$in_done1_parent,
]


# Remove duplicate copies of the same annotation event
# appearing in different source-file versions.
#
# Label-event identity =
# recording + exact File Offset + label.

label_rows <- label_rows[
  !duplicated(
    label_rows[
      ,
      c(
        "Begin File",
        "File Offset (s)",
        "label_clean"
      )
    ]
  ),
]

cat(
  "Unique label events inside Done = 1 parent segments:",
  nrow(label_rows),
  "\n"
)


# ---- 7. Prepare Common Names for QC ----

# Preserve exactly what was entered.
label_rows$common_name_raw <- as.character(
  label_rows$`Common Name`
)

# Remove accidental whitespace while preserving
# spelling and capitalization.
label_rows$common_name_clean <- trimws(
  label_rows$common_name_raw
)

label_rows$common_name_clean <- gsub(
  "\\s+",
  " ",
  label_rows$common_name_clean
)

# Lowercase copy used ONLY as a comparison key.
label_rows$common_name_match <- tolower(
  label_rows$common_name_clean
)


# ---- 8. Find missing Common Names requiring review ----

missing_common_name <- label_rows[
  is.na(label_rows$common_name_clean) |
    label_rows$common_name_clean == "",
  c(
    "source_file",
    "Begin File",
    "File Offset (s)",
    "Label",
    "Common Name"
  )
]

cat(
  "Missing Common Names requiring review:",
  nrow(missing_common_name),
  "\n"
)

write.csv(
  missing_common_name,
  "output/qc/00_missing_names_for_review.csv",
  row.names = FALSE
)


# Summarize missing Common Names by Label.

if (nrow(missing_common_name) > 0) {
  
  missing_name_summary <- aggregate(
    list(events = rep(1, nrow(missing_common_name))),
    by = list(Label = missing_common_name$Label),
    FUN = sum
  )
  
  missing_name_summary <- missing_name_summary[
    order(-missing_name_summary$events),
  ]
  
} else {
  
  missing_name_summary <- data.frame(
    Label = character(),
    events = integer()
  )
}

write.csv(
  missing_name_summary,
  "output/qc/00_missing_name_summary.csv",
  row.names = FALSE
)

cat("\nMissing Common Names by Label:\n")
print(missing_name_summary, row.names = FALSE)


# Keep only rows with a Common Name for BirdNET matching.

named_species_rows <- label_rows[
  !is.na(label_rows$common_name_clean) &
    label_rows$common_name_clean != "",
]


# ---- 9. Read BirdNET v2.4 canonical labels ----

if (!file.exists(birdnet_label_file)) {
  stop(
    paste(
      "BirdNET label file not found:",
      birdnet_label_file
    )
  )
}

birdnet_labels <- readLines(
  birdnet_label_file,
  warn = FALSE,
  encoding = "UTF-8"
)

birdnet_labels <- trimws(birdnet_labels)
birdnet_labels <- birdnet_labels[birdnet_labels != ""]

# BirdNET format:
# Scientific name_Common name

birdnet_common_names <- sub(
  "^[^_]+_",
  "",
  birdnet_labels
)

birdnet_common_match <- tolower(
  birdnet_common_names
)

# Our Common Name crosswalk requires unique BirdNET
# Common Names.
if (anyDuplicated(birdnet_common_match)) {
  stop("Duplicate Common Names found in BirdNET label file.")
}


# ---- 10. Define approved novel classes ----

# Custom classes that intentionally do not exist
# in BirdNET's source taxonomy.

novel_classes <- c(
  "Water"
)

novel_match <- tolower(novel_classes)


# ---- 11. Summarize Common Names used in annotations ----

name_review <- aggregate(
  list(annotation_events = rep(1, nrow(named_species_rows))),
  by = list(
    common_name_raw =
      named_species_rows$common_name_raw,
    common_name_clean =
      named_species_rows$common_name_clean,
    common_name_match =
      named_species_rows$common_name_match
  ),
  FUN = sum
)


# ---- 12. Match names to BirdNET or novel classes ----

birdnet_index <- match(
  name_review$common_name_match,
  birdnet_common_match
)

novel_index <- match(
  name_review$common_name_match,
  novel_match
)

name_review$canonical_name <- NA_character_
name_review$match_status <- "REVIEW"


# BirdNET matches.

is_birdnet <- !is.na(birdnet_index)

name_review$canonical_name[is_birdnet] <-
  birdnet_common_names[birdnet_index[is_birdnet]]

name_review$match_status[is_birdnet] <-
  "BirdNET exact match"


# Harmless formatting differences such as capitalization
# or extra spaces.

format_differs <-
  is_birdnet &
  name_review$common_name_clean !=
  name_review$canonical_name

name_review$match_status[format_differs] <-
  "BirdNET match - formatting differs"


# Approved novel classes.

is_novel <- !is.na(novel_index)

name_review$canonical_name[is_novel] <-
  novel_classes[novel_index[is_novel]]

name_review$match_status[is_novel] <-
  "Approved novel class"


# ---- 13. Suggest fuzzy matches for unmatched names ----

# Suggestions are for human review ONLY.
# Nothing is automatically corrected.

name_review$suggestion_1 <- NA_character_
name_review$distance_1 <- NA_integer_

name_review$suggestion_2 <- NA_character_
name_review$distance_2 <- NA_integer_

name_review$suggestion_3 <- NA_character_
name_review$distance_3 <- NA_integer_

review_rows <- which(
  name_review$match_status == "REVIEW"
)

for (i in review_rows) {
  
  distances <- as.numeric(
    adist(
      name_review$common_name_match[i],
      birdnet_common_match
    )
  )
  
  closest <- order(distances)[
    1:min(3, length(distances))
  ]
  
  name_review$suggestion_1[i] <-
    birdnet_common_names[closest[1]]
  
  name_review$distance_1[i] <-
    distances[closest[1]]
  
  if (length(closest) >= 2) {
    
    name_review$suggestion_2[i] <-
      birdnet_common_names[closest[2]]
    
    name_review$distance_2[i] <-
      distances[closest[2]]
  }
  
  if (length(closest) >= 3) {
    
    name_review$suggestion_3[i] <-
      birdnet_common_names[closest[3]]
    
    name_review$distance_3[i] <-
      distances[closest[3]]
  }
}


# ---- 14. Save Common Name review ----

name_review <- name_review[
  order(
    name_review$match_status,
    name_review$common_name_clean
  ),
]

write.csv(
  name_review,
  "output/qc/00_common_name_review.csv",
  row.names = FALSE
)


# ---- 15. Save names requiring human review ----

needs_review <- name_review[
  name_review$match_status == "REVIEW",
]

write.csv(
  needs_review,
  "output/qc/00_unmatched_names_for_review.csv",
  row.names = FALSE
)

cat(
  "\nNames requiring human review:",
  nrow(needs_review),
  "\n"
)

if (nrow(needs_review) > 0) {
  
  print(
    needs_review[
      ,
      c(
        "common_name_raw",
        "annotation_events",
        "suggestion_1",
        "distance_1",
        "suggestion_2",
        "distance_2",
        "suggestion_3",
        "distance_3"
      )
    ],
    row.names = FALSE
  )
}


# ---- 16. Create permanent human correction log ----

correction_file <-
  "output/qc/00_annotation_corrections.csv"

# Never overwrite an existing human-reviewed correction log.

if (!file.exists(correction_file)) {
  
  correction_log <- data.frame(
    scope = character(),
    begin_file = character(),
    file_offset_s = numeric(),
    label = character(),
    entered_common_name = character(),
    action = character(),
    resolved_common_name = character(),
    status = character(),
    note = character(),
    stringsAsFactors = FALSE
  )
  
  write.csv(
    correction_log,
    correction_file,
    row.names = FALSE
  )
  
  cat(
    "\nCreated correction log:",
    correction_file,
    "\n"
  )
  
} else {
  
  cat(
    "\nExisting correction log preserved:",
    correction_file,
    "\n"
  )
}


# ---- 17. Final summary ----

cat("\n================ PRECHECK SUMMARY ================\n")

cat(
  "Source files:",
  length(source_files),
  "\n"
)

cat(
  "Unique label events inside Done = 1 parent segments:",
  nrow(label_rows),
  "\n"
)

cat(
  "Missing Common Names requiring review:",
  nrow(missing_common_name),
  "\n"
)

cat(
  "Unique entered Common Names:",
  nrow(name_review),
  "\n"
)

cat(
  "Formatting-only variants:",
  sum(
    name_review$match_status ==
      "BirdNET match - formatting differs"
  ),
  "\n"
)

cat(
  "Names requiring human review:",
  nrow(needs_review),
  "\n"
)

cat("==================================================\n")