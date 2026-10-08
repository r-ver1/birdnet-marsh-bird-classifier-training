# ============================================================
# 02_build_pilot_segment_manifest.R
#
# Build segment manifest for the pilot
# KIRA/RWBL BirdNET transfer-learning dataset.
#
# Inputs are the validated outputs from Script 00b.
#
# Important:
#   - Parent identity = Begin File + exact parent_start
#   - Parent starts are NEVER rounded
#   - Positive classes are reconstructed from resolved Label values
#     beginning within [parent_start, parent_start + 3)
#   - Common Name from Verify = 0 BirdNET rows is not used as
#     biological identity; confirmed/manual positive rows supply identity
#   - Existing BirdNET classes use exact matching BirdNET v2.4 labels
#   - Water is retained as an approved novel class
#   - NT, Noise, and Background Noise are not positive classes
#   - No WAV files are created by this script
# ============================================================


# ---- 1. Paths ----

clean_file <- "output/qc/00b_pilot_annotations_cleaned.rds"

parent_file <-
  "output/qc/00b_includable_done1_parent_segments.rds"

birdnet_label_file <-
  "D:/BirdNET_GLOBAL_6K_V2.4_Labels.txt"

output_dir <- "output/manifest"

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


# ---- 2. Confirm required input files exist ----

required_files <- c(
  clean_file,
  parent_file,
  birdnet_label_file
)

missing_files <- required_files[!file.exists(required_files)]

if (length(missing_files) > 0) {
  stop(
    "Missing required input file(s):\n",
    paste(missing_files, collapse = "\n")
  )
}


# ---- 3. Read validated Script 00b outputs ----

annotations <- readRDS(clean_file)
parents <- readRDS(parent_file)

required_annotation_columns <- c(
  "Begin File",
  "Begin Path",
  "File Offset (s)",
  "Common Name",
  "Species Code",
  "Confidence",
  "Verify",
  "Label",
  "Done?"
)

missing_columns <- setdiff(
  required_annotation_columns,
  names(annotations)
)

if (length(missing_columns) > 0) {
  stop(
    "Cleaned annotation file is missing required columns: ",
    paste(missing_columns, collapse = ", ")
  )
}

if (!all(c("Begin File", "parent_start") %in% names(parents))) {
  stop(
    "Includable-parent file must contain Begin File and parent_start."
  )
}


# ---- 4. Standard working columns ----
#
# Create the numeric/text fields needed by this script.

if (!"offset_num" %in% names(annotations)) {
  annotations$offset_num <-
    suppressWarnings(as.numeric(annotations[["File Offset (s)"]]))
}

if (!"done_num" %in% names(annotations)) {
  annotations$done_num <-
    suppressWarnings(as.numeric(annotations[["Done?"]]))
}

if (!"verify_num" %in% names(annotations)) {
  annotations$verify_num <-
    suppressWarnings(as.numeric(annotations[["Verify"]]))
}

if (!"label_clean" %in% names(annotations)) {
  annotations$label_clean <- trimws(annotations[["Label"]])
}

annotations$label_clean[is.na(annotations$label_clean)] <- ""

annotations$common_clean <- trimws(annotations[["Common Name"]])
annotations$common_clean[is.na(annotations$common_clean)] <- ""


# ---- 5. Read exact BirdNET v2.4 class labels ----

birdnet_labels <- readLines(
  birdnet_label_file,
  warn = FALSE,
  encoding = "UTF-8"
)

birdnet_labels <- sub("^\ufeff", "", birdnet_labels)
birdnet_labels <- trimws(birdnet_labels)
birdnet_labels <- birdnet_labels[nzchar(birdnet_labels)]

# BirdNET labels use:
# Scientific name_Common name
birdnet_common_names <- sub(
  "^[^_]+_",
  "",
  birdnet_labels
)

birdnet_lookup <- setNames(
  birdnet_labels,
  birdnet_common_names
)


# ---- 6. Define manifest label outcomes ----

# These annotations contribute no positive training class.
ignored_labels <- c(
  "",
  "NT",
  "Noise",
  "Background Noise"
)

# Approved project class that is not a BirdNET source class.
novel_labels <- c("Water")


# ---- 7. Preserve annotation path provenance ----
#
# The same recording may be referenced from multiple historical
# annotation folders. For this pilot, recording identity is defined
# by Begin File, and segment identity by Begin File + exact parent_start.
#
# Verify that every historical Begin Path ends in the stated Begin File,
# and retain all unique paths as provenance. The actual source WAV will
# be located and uniquely verified during audio extraction.

path_rows <- which(
  nzchar(trimws(annotations[["Begin Path"]])) &
    nzchar(trimws(annotations[["Begin File"]]))
)

path_pairs <- unique(
  annotations[
    path_rows,
    c("Begin File", "Begin Path")
  ]
)

path_basenames <- sub(
  "^.*[\\\\/]",
  "",
  trimws(path_pairs[["Begin Path"]])
)

if (any(path_basenames != path_pairs[["Begin File"]])) {
  stop(
    "At least one Begin Path does not end in its stated Begin File."
  )
}

annotation_path_lookup <- tapply(
  path_pairs[["Begin Path"]],
  path_pairs[["Begin File"]],
  function(x) paste(sort(unique(x)), collapse = " | ")
)


# ---- 8. Helper: reconstruct labels for one parent segment ----
#
# A label belongs to the parent if its File Offset begins within:
#
# parent_start <= label_offset < parent_start + 3
#
# This follows the annotation decision already documented for
# the project. Frequency overlap and annotation duration do not
# redefine parent membership.

get_segment_labels <- function(begin_file, parent_start) {
  
  member_rows <- which(
    annotations[["Begin File"]] == begin_file &
      !is.na(annotations$offset_num) &
      annotations$offset_num >= parent_start &
      annotations$offset_num < parent_start + 3
  )
  
  segment_rows <- annotations[member_rows, , drop = FALSE]
  
  observed_labels <- unique(segment_rows$label_clean)
  
  # Ignore non-positive labels case-insensitively so harmless
  # capitalization differences such as Noise/noise do not become classes.
  retained_labels <- observed_labels[
    !tolower(observed_labels) %in% tolower(ignored_labels)
  ]
  
  annotation_labels <- character()
  common_names <- character()
  model_labels <- character()
  
  for (lab in retained_labels) {
    
    # Water is an approved novel project class.
    if (lab %in% novel_labels) {
      
      annotation_labels <- c(annotation_labels, lab)
      common_names <- c(common_names, lab)
      model_labels <- c(model_labels, lab)
      
      next
    }
    
    rows_for_label <- segment_rows[
      segment_rows$label_clean == lab,
      ,
      drop = FALSE
    ]
    
    # Common Name on a rejected BirdNET prediction (Verify = 0)
    # is the rejected classifier identity, not biological truth.
    # Use Common Name only from a confirmed BirdNET prediction
    # (Verify = 1) or from a manually drawn label row (Verify blank).
    verify_value <- trimws(
      as.character(rows_for_label[["Verify"]])
    )
    verify_value[is.na(verify_value)] <- ""
    
    identity_rows <- rows_for_label[
      verify_value %in% c("", "1"),
      ,
      drop = FALSE
    ]
    
    possible_common <- unique(
      identity_rows$common_clean[
        nzchar(identity_rows$common_clean)
      ]
    )
    
    # Script 00b already validated Common Names against BirdNET
    # case-insensitively. Match that way here too, then use
    # BirdNET's exact canonical spelling in the manifest.
    common_matches <- match(
      tolower(possible_common),
      tolower(birdnet_common_names)
    )
    
    if (any(is.na(common_matches))) {
      stop(
        "Manifest found a Common Name that could not be matched ",
        "to BirdNET v2.4 for label '",
        lab,
        "' in ",
        begin_file,
        " at ",
        parent_start,
        " s."
      )
    }
    
    canonical_common <- unique(
      birdnet_common_names[common_matches]
    )
    
    if (length(canonical_common) != 1) {
      stop(
        "Manifest could not assign exactly one Common Name for label '",
        lab,
        "' in ",
        begin_file,
        " at ",
        parent_start,
        " s."
      )
    }
    
    common_name <- canonical_common[1]
    
    birdnet_label <- unname(
      birdnet_lookup[common_name]
    )
    
    # Do not silently discard a resolved biological annotation.
    if (
      length(birdnet_label) != 1 ||
      is.na(birdnet_label) ||
      !nzchar(birdnet_label)
    ) {
      stop(
        "Resolved label '",
        lab,
        "' (",
        common_name,
        ") could not be mapped to BirdNET v2.4 in ",
        begin_file,
        " at ",
        parent_start,
        " s."
      )
    }
    
    annotation_labels <- c(
      annotation_labels,
      lab
    )
    
    common_names <- c(
      common_names,
      common_name
    )
    
    model_labels <- c(
      model_labels,
      birdnet_label
    )
  }
  
  # Some older focal-review records confirm a biological class
  # with Common Name + Verify = 1 but do not repeat that class
  # in Label. Retain those confirmed positives as well.
  verified_unlabeled <- segment_rows[
    !is.na(segment_rows$verify_num) &
      segment_rows$verify_num == 1 &
      segment_rows$label_clean == "" &
      nzchar(segment_rows$common_clean),
    ,
    drop = FALSE
  ]
  
  if (nrow(verified_unlabeled) > 0) {
    
    verified_matches <- match(
      tolower(verified_unlabeled$common_clean),
      tolower(birdnet_common_names)
    )
    
    # Non-BirdNET values such as Noise are not positive species classes.
    verified_matches <- verified_matches[
      !is.na(verified_matches)
    ]
    
    if (length(verified_matches) > 0) {
      
      verified_common <- unique(
        birdnet_common_names[verified_matches]
      )
      
      common_names <- c(
        common_names,
        verified_common
      )
      
      model_labels <- c(
        model_labels,
        unname(birdnet_lookup[verified_common])
      )
    }
  }
  
  list(
    annotation_labels = sort(unique(annotation_labels)),
    common_names = sort(unique(common_names)),
    model_labels = sort(unique(model_labels))
  )
}


# ---- 9. Build manifest for includable Done = 1 parents ----

parents <- unique(
  parents[, c("Begin File", "parent_start")]
)

parents <- parents[
  order(
    parents[["Begin File"]],
    parents$parent_start
  ),
]

labeled_manifest <- vector(
  "list",
  nrow(parents)
)

class_records <- list()
class_record_i <- 1L


for (i in seq_len(nrow(parents))) {
  
  begin_file <- parents[["Begin File"]][i]
  parent_start <- parents$parent_start[i]
  
  labels <- get_segment_labels(
    begin_file,
    parent_start
  )
  
  annotation_paths <- unname(
    annotation_path_lookup[begin_file]
  )
  
  if (
    length(annotation_paths) != 1 ||
    is.na(annotation_paths) ||
    !nzchar(annotation_paths)
  ) {
    stop(
      "No annotation path metadata found for ",
      begin_file
    )
  }
  
  labeled_manifest[[i]] <- data.frame(
    segment_type = "reviewed",
    `Begin File` = begin_file,
    annotation_path_candidates = annotation_paths,
    parent_start = parent_start,
    parent_end = parent_start + 3,
    annotation_labels = paste(
      labels$annotation_labels,
      collapse = ", "
    ),
    common_names = paste(
      labels$common_names,
      collapse = ", "
    ),
    model_labels = paste(
      labels$model_labels,
      collapse = ", "
    ),
    n_model_labels = length(labels$model_labels),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  
  if (length(labels$model_labels) > 0) {
    
    for (j in seq_along(labels$model_labels)) {
      
      model_label <- labels$model_labels[j]
      
      if (model_label == "Water") {
        common_name <- "Water"
      } else {
        common_name <- sub(
          "^[^_]+_",
          "",
          model_label
        )
      }
      
      class_records[[class_record_i]] <- data.frame(
        `Begin File` = begin_file,
        parent_start = parent_start,
        model_label = model_label,
        common_name = common_name,
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
      
      class_record_i <- class_record_i + 1L
    }
  }
}

labeled_manifest <- do.call(
  rbind,
  labeled_manifest
)


# ---- 10. Reconcile Verify = 1 predictions with manifest labels ----
#
# Checks that the new manifest reconstruction has not dropped a confirmed species.

verify_mismatches <- list()
mismatch_i <- 1L

for (i in seq_len(nrow(parents))) {
  
  begin_file <- parents[["Begin File"]][i]
  parent_start <- parents$parent_start[i]
  
  anchor_rows <- which(
    annotations[["Begin File"]] == begin_file &
      !is.na(annotations$offset_num) &
      annotations$offset_num == parent_start
  )
  
  anchor <- annotations[
    anchor_rows,
    ,
    drop = FALSE
  ]
  
  # Verify = 1 confirms the Common Name biologically.
  # Reconcile only names that are actual BirdNET classes;
  # non-biological values such as Noise are ignored here.
  # Reconcile only Verify = 1 rows that represent positive
  # training classes under the same rules used to build the manifest.
  # Explicitly ignored labels such as Noise do not become positives
  # merely because Verify = 1 was entered on the manual selection.
  verified_positive <- (
    !is.na(anchor$verify_num) &
      anchor$verify_num == 1 &
      nzchar(anchor$common_clean) &
      (
        anchor$label_clean == "" |
          !tolower(anchor$label_clean) %in% tolower(ignored_labels)
      )
  )
  
  verified_raw <- unique(
    anchor$common_clean[
      verified_positive
    ]
  )
  
  verified_matches <- match(
    tolower(verified_raw),
    tolower(birdnet_common_names)
  )
  
  verified_common <- unique(
    birdnet_common_names[
      verified_matches[!is.na(verified_matches)]
    ]
  )
  
  if (length(verified_common) == 0) {
    next
  }
  
  manifest_common <- strsplit(
    labeled_manifest$common_names[i],
    ", ",
    fixed = TRUE
  )[[1]]
  
  manifest_common <- manifest_common[
    nzchar(manifest_common)
  ]
  
  missing_verified <- setdiff(
    verified_common,
    manifest_common
  )
  
  if (length(missing_verified) > 0) {
    
    for (common_name in missing_verified) {
      
      verify_mismatches[[mismatch_i]] <- data.frame(
        `Begin File` = begin_file,
        parent_start = parent_start,
        verified_common_name = common_name,
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
      
      mismatch_i <- mismatch_i + 1L
    }
  }
}

if (length(verify_mismatches) > 0) {
  
  verify_mismatches <- do.call(
    rbind,
    verify_mismatches
  )
  
  print(verify_mismatches)
  
  stop(
    "At least one Verify = 1 species was lost during ",
    "manifest reconstruction. Review the rows printed above."
  )
}


# ---- 11. Build and validate Done = 2 background segments ----

background_rows <- which(
  !is.na(annotations$done_num) &
    annotations$done_num == 2 &
    !is.na(annotations$offset_num) &
    nzchar(annotations[["Begin File"]])
)

background_parents <- unique(
  data.frame(
    `Begin File` =
      annotations[["Begin File"]][background_rows],
    
    parent_start =
      annotations$offset_num[background_rows],
    
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
)

background_parents <- background_parents[
  order(
    background_parents[["Begin File"]],
    background_parents$parent_start
  ),
]

background_manifest <- vector(
  "list",
  nrow(background_parents)
)


for (i in seq_len(nrow(background_parents))) {
  
  begin_file <- background_parents[["Begin File"]][i]
  parent_start <- background_parents$parent_start[i]
  
  labels <- get_segment_labels(
    begin_file,
    parent_start
  )
  
  # A background segment cannot also contain a class that this
  # manifest intends to use as a positive training class.
  # Includes: Water (novel class)
  biological_names <- setdiff(
    labels$common_names,
    "Water"
  )
  
  if (length(biological_names) > 0) {
    
    message(
      "Excluding Done = 2 background segment with biological label(s): ",
      paste(biological_names, collapse = ", "),
      " | ",
      begin_file,
      " at ",
      parent_start,
      " s."
    )
    
    next
  }
  
  annotation_paths <- unname(
    annotation_path_lookup[begin_file]
  )
  
  if (
    length(annotation_paths) != 1 ||
    is.na(annotation_paths) ||
    !nzchar(annotation_paths)
  ) {
    stop(
      "No annotation path metadata found for background recording ",
      begin_file
    )
  }
  
  background_manifest[[i]] <- data.frame(
    segment_type = "Background",
    `Begin File` = begin_file,
    annotation_path_candidates = annotation_paths,
    parent_start = parent_start,
    parent_end = parent_start + 3,
    annotation_labels = "",
    common_names = "",
    model_labels = "",
    n_model_labels = 0L,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

background_manifest <- do.call(
  rbind,
  background_manifest
)


# ---- 12. Combine authoritative manifest ----

manifest <- rbind(
  labeled_manifest,
  background_manifest
)

manifest <- manifest[
  order(
    manifest$segment_type,
    manifest[["Begin File"]],
    manifest$parent_start
  ),
]

rownames(manifest) <- NULL


# ---- 13. Build class inventory ----

if (length(class_records) > 0) {
  
  class_long <- do.call(
    rbind,
    class_records
  )
  
  class_inventory <- aggregate(
    list(segment_count = class_long$model_label),
    by = list(
      model_label = class_long$model_label,
      common_name = class_long$common_name
    ),
    FUN = length
  )
  
  class_inventory$class_type <- ifelse(
    class_inventory$model_label == "Water",
    "approved_novel",
    "BirdNET_v2.4"
  )
  
  class_inventory <- class_inventory[
    order(
      -class_inventory$segment_count,
      class_inventory$common_name
    ),
  ]
  
} else {
  
  class_inventory <- data.frame(
    model_label = character(),
    common_name = character(),
    segment_count = integer(),
    class_type = character(),
    stringsAsFactors = FALSE
  )
}


# ---- 14. Save outputs ----

write.csv(
  manifest,
  file.path(
    output_dir,
    "02_pilot_segment_manifest.csv"
  ),
  row.names = FALSE
)

write.csv(
  class_inventory,
  file.path(
    output_dir,
    "02_pilot_class_inventory.csv"
  ),
  row.names = FALSE
)


# ---- 15. Print review summary ----

zero_label_segments <- sum(
  labeled_manifest$n_model_labels == 0
)

cat("\n")
cat("============= PILOT SEGMENT MANIFEST =============\n")
cat(
  "Reviewed Done = 1 segments: ",
  nrow(labeled_manifest),
  "\n",
  sep = ""
)
cat(
  "Background Done = 2 segments: ",
  nrow(background_manifest),
  "\n",
  sep = ""
)
cat(
  "Total manifest segments: ",
  nrow(manifest),
  "\n",
  sep = ""
)
cat(
  "Reviewed segments with zero retained positive classes: ",
  zero_label_segments,
  "\n\n",
  sep = ""
)

cat("Classes retained for training:\n")
print(
  class_inventory,
  row.names = FALSE
)

cat("\nOutputs:\n")
cat(
  file.path(
    output_dir,
    "02_pilot_segment_manifest.csv"
  ),
  "\n"
)
cat(
  file.path(
    output_dir,
    "02_pilot_class_inventory.csv"
  ),
  "\n"
)
cat("==================================================\n")