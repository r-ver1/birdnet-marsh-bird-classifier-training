# ============================================================
# 01_audit_focal_counts.R
#
# Audit focal-species segment counts after annotation cleanup.
#
# Reports:
#   1. Raw reviewed focal counts from original source annotations
#   2. Pilot-eligible focal counts after 00b exclusions
#   3. Focal-label presence within 3-second parent segments
#   4. Background segment count
#   5. Focal counts by recording and recorder
#
# IMPORTANT:
# Raw reviewed counts and pilot-eligible counts are kept
# separate. Excluding an ambiguous parent segment from this
# pilot does not erase the original annotation record.
# ============================================================


# ---- 1. Set paths and focal-species configuration ----

dir.create(
  "output/qc",
  recursive = TRUE,
  showWarnings = FALSE
)

clean_file <-
  "output/qc/00b_pilot_annotations_cleaned.rds"

includable_file <-
  "output/qc/00b_includable_done1_parent_segments.rds"

excluded_file <-
  "output/qc/00b_excluded_parent_segments.csv"


if (
  !file.exists(clean_file) ||
  !file.exists(includable_file) ||
  !file.exists(excluded_file)
) {
  stop(
    "Required 00b outputs are missing. Run 00b successfully before Script 01."
  )
}


# Edit this named vector when the expanded focal-species
# annotation set is added.
#
# Names = annotation Label codes
# Values = canonical Common Names.

focal_map <- c(
  "KIRA" = "King Rail",
  "RWBL" = "Red-winged Blackbird"
)

focal_codes <- names(focal_map)
focal_species <- unname(focal_map)


# ---- 2. Read original source annotations ----
#
# These are retained so we can preserve the raw reviewed counts
# as a QC record separate from pilot eligibility.

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

source_files <- c(
  ann_files[basename(ann_files) != "combined_annotations.csv"],
  bg_files[basename(bg_files) != "combined_annotations.csv"]
)


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


all_annotations$done_num <- suppressWarnings(
  as.numeric(all_annotations$`Done?`)
)

all_annotations$verify_num <- suppressWarnings(
  as.numeric(all_annotations$Verify)
)

all_annotations$offset_num <- suppressWarnings(
  as.numeric(all_annotations$`File Offset (s)`)
)


# ---- 3. Load cleaned pilot annotations and eligible parents ----
#
# clean_annotations contains the approved 00b corrections.
#
# includable_parents contains only Done? = 1 parent segments
# that remain usable after whole-segment exclusion of unresolved
# annotations.

clean_annotations <- readRDS(clean_file)

includable_parents <- readRDS(
  includable_file
)

excluded_parents <- read.csv(
  excluded_file,
  check.names = FALSE,
  stringsAsFactors = FALSE
)


# Recreate numeric fields defensively if needed.

clean_annotations$done_num <- suppressWarnings(
  as.numeric(clean_annotations$`Done?`)
)

clean_annotations$verify_num <- suppressWarnings(
  as.numeric(clean_annotations$Verify)
)

clean_annotations$offset_num <- suppressWarnings(
  as.numeric(clean_annotations$`File Offset (s)`)
)


# ---- 4. Identify raw Done? = 1 parent segments ----

raw_done1_parents <- unique(
  all_annotations[
    which(
      all_annotations$done_num == 1 &
        !is.na(all_annotations$`Begin File`) &
        !is.na(all_annotations$offset_num)
    ),
    c(
      "Begin File",
      "offset_num"
    )
  ]
)

names(raw_done1_parents)[2] <- "parent_start"


# Confirm that 00b eligibility accounts for every completed
# parent segment.

if (
  nrow(raw_done1_parents) -
  nrow(includable_parents) !=
  nrow(excluded_parents)
) {
  
  stop(
    "Raw, excluded, and includable parent-segment counts do not reconcile."
  )
}


# ---- 5. Helper: count positive and negative focal reviews ----

count_focal_reviews <- function(df) {
  
  tab <- table(
    factor(
      df$focal_name,
      levels = focal_species
    ),
    factor(
      df$verify_num,
      levels = c(0, 1)
    )
  )
  
  data.frame(
    `Common Name` = focal_species,
    positive_segments = as.integer(tab[, "1"]),
    negative_segments = as.integer(tab[, "0"]),
    check.names = FALSE
  )
}


# ---- 6. Raw completed focal-species reviews ----
#
# Done? = 1 = completed focal review
# Verify = 1 = positive
# Verify = 0 = negative
#
# These are the original reviewed counts BEFORE pilot exclusions.

raw_focal_reviews <- all_annotations[
  which(
    all_annotations$done_num == 1 &
      all_annotations$`Common Name` %in% focal_species &
      all_annotations$verify_num %in% c(0, 1)
  ),
]

raw_focal_reviews$focal_name <-
  raw_focal_reviews$`Common Name`


# Check that repeated source-file versions do not disagree
# about the completed Verify result for the same focal review.

raw_conflict_check <- aggregate(
  list(
    n_verify = raw_focal_reviews$verify_num
  ),
  by = list(
    Begin_File = raw_focal_reviews$`Begin File`,
    offset_num = raw_focal_reviews$offset_num,
    Common_Name = raw_focal_reviews$focal_name
  ),
  FUN = function(x) length(unique(x))
)

if (any(raw_conflict_check$n_verify > 1)) {
  stop(
    "Conflicting completed Verify results found in raw focal reviews."
  )
}


# Collapse redundant copies across annotation versions.

raw_focal_unique <- unique(
  raw_focal_reviews[
    ,
    c(
      "Begin File",
      "offset_num",
      "focal_name",
      "verify_num"
    )
  ]
)

raw_counts <- count_focal_reviews(
  raw_focal_unique
)

names(raw_counts)[2:3] <- c(
  "raw_positive_segments",
  "raw_negative_segments"
)


# ---- 7. Pilot-eligible completed focal reviews ----
#
# Common Names have already been cleaned in 00b.
#
# Matching here is case-insensitive so harmless formatting
# differences cannot make a focal review disappear.

common_clean <- gsub(
  "\\s+",
  " ",
  trimws(
    as.character(
      clean_annotations$`Common Name`
    )
  )
)

focal_index <- match(
  tolower(common_clean),
  tolower(focal_species)
)

clean_annotations$focal_name <-
  focal_species[focal_index]


pilot_focal_reviews <- clean_annotations[
  which(
    clean_annotations$done_num == 1 &
      !is.na(clean_annotations$focal_name) &
      clean_annotations$verify_num %in% c(0, 1)
  ),
  c(
    "Begin File",
    "offset_num",
    "focal_name",
    "verify_num"
  )
]


# Keep only focal reviews whose parent segment survived 00b.

pilot_focal_reviews <- merge(
  pilot_focal_reviews,
  includable_parents,
  by.x = c(
    "Begin File",
    "offset_num"
  ),
  by.y = c(
    "Begin File",
    "parent_start"
  ),
  all = FALSE,
  sort = FALSE
)


# Check for conflicting completed review results after cleanup.

pilot_conflict_check <- aggregate(
  list(
    n_verify = pilot_focal_reviews$verify_num
  ),
  by = list(
    Begin_File = pilot_focal_reviews$`Begin File`,
    offset_num = pilot_focal_reviews$offset_num,
    Common_Name = pilot_focal_reviews$focal_name
  ),
  FUN = function(x) length(unique(x))
)

if (any(pilot_conflict_check$n_verify > 1)) {
  stop(
    "Conflicting completed Verify results found in pilot-eligible focal reviews."
  )
}


# Collapse redundant annotation-file versions.

pilot_focal_unique <- unique(
  pilot_focal_reviews[
    ,
    c(
      "Begin File",
      "offset_num",
      "focal_name",
      "verify_num"
    )
  ]
)


pilot_counts <- count_focal_reviews(
  pilot_focal_unique
)

names(pilot_counts)[2:3] <- c(
  "pilot_positive_segments",
  "pilot_negative_segments"
)


# ---- 8. Count focal labels inside 3-second parent segments ----
#
# A focal species is present when its Label code occurs anywhere
# within:
#
#   parent_start <= label offset < parent_start + 3
#
# Multiple occurrences of the same species in one parent count
# only once.

count_label_presence <- function(
    annotations,
    parents,
    code_map
) {
  
  label_clean <- trimws(
    as.character(annotations$Label)
  )
  
  label_start <- suppressWarnings(
    as.numeric(
      annotations$`File Offset (s)`
    )
  )
  
  out <- integer(
    length(code_map)
  )
  
  names(out) <- names(code_map)
  
  
  for (code in names(code_map)) {
    
    rows <- which(
      label_clean == code &
        !is.na(annotations$`Begin File`) &
        !is.na(label_start)
    )
    
    out[code] <- sum(
      vapply(
        seq_len(nrow(parents)),
        function(i) {
          
          any(
            annotations$`Begin File`[rows] ==
              parents$`Begin File`[i] &
              label_start[rows] >=
              parents$parent_start[i] &
              label_start[rows] <
              parents$parent_start[i] + 3,
            na.rm = TRUE
          )
        },
        logical(1)
      )
    )
  }
  
  out
}


# Raw label-presence counts reproduce the original annotation
# audit before pilot exclusions.

raw_label_presence <- count_label_presence(
  all_annotations,
  raw_done1_parents,
  focal_map
)


# Pilot label-presence counts use cleaned labels and only the
# 441 currently includable parent segments.

pilot_label_presence <- count_label_presence(
  clean_annotations,
  includable_parents,
  focal_map
)


label_presence <- data.frame(
  `Common Name` = focal_species,
  
  raw_label_present_segments =
    as.integer(
      raw_label_presence[focal_codes]
    ),
  
  pilot_label_present_segments =
    as.integer(
      pilot_label_presence[focal_codes]
    ),
  
  check.names = FALSE
)


# ---- 9. Combine focal summary ----

focal_summary <- merge(
  raw_counts,
  pilot_counts,
  by = "Common Name",
  all = TRUE
)

focal_summary <- merge(
  focal_summary,
  label_presence,
  by = "Common Name",
  all = TRUE
)

focal_summary[is.na(focal_summary)] <- 0

focal_summary <- focal_summary[
  match(
    focal_species,
    focal_summary$`Common Name`
  ),
]


# ---- 10. Count unique background segments ----
#
# Done? = 2 defines background.
#
# The 00b ambiguity exclusions apply to completed Done? = 1
# labeled parent segments, so background is retained as its
# own raw segment count here.

background_unique <- unique(
  all_annotations[
    which(
      all_annotations$done_num == 2 &
        !is.na(all_annotations$`Begin File`) &
        !is.na(all_annotations$offset_num)
    ),
    c(
      "Begin File",
      "offset_num"
    )
  ]
)


# ---- 11. Summarize pilot focal reviews by recording ----

count_by_status <- function(
    df,
    group_columns
) {
  
  count_subset <- function(
    x,
    output_name
  ) {
    
    if (nrow(x) == 0) {
      
      out <- df[
        FALSE,
        group_columns,
        drop = FALSE
      ]
      
      out[[output_name]] <- integer(0)
      
      return(out)
    }
    
    out <- aggregate(
      list(
        count = rep(
          1L,
          nrow(x)
        )
      ),
      by = x[group_columns],
      FUN = sum
    )
    
    names(out)[ncol(out)] <-
      output_name
    
    out
  }
  
  
  positive <- count_subset(
    df[df$verify_num == 1, ],
    "positive_segments"
  )
  
  negative <- count_subset(
    df[df$verify_num == 0, ],
    "negative_segments"
  )
  
  
  out <- merge(
    positive,
    negative,
    by = group_columns,
    all = TRUE
  )
  
  out$positive_segments[
    is.na(out$positive_segments)
  ] <- 0
  
  out$negative_segments[
    is.na(out$negative_segments)
  ] <- 0
  
  out
}


focal_by_file <- count_by_status(
  pilot_focal_unique,
  c(
    "Begin File",
    "focal_name"
  )
)

names(focal_by_file)[
  names(focal_by_file) == "focal_name"
] <- "Common Name"

focal_by_file <- focal_by_file[
  order(
    focal_by_file$`Common Name`,
    focal_by_file$`Begin File`
  ),
]


# ---- 12. Summarize pilot focal reviews by recorder ----

pilot_focal_unique$recorder <- sub(
  "_.*$",
  "",
  pilot_focal_unique$`Begin File`
)

focal_by_recorder <- count_by_status(
  pilot_focal_unique,
  c(
    "recorder",
    "focal_name"
  )
)

names(focal_by_recorder)[
  names(focal_by_recorder) == "focal_name"
] <- "Common Name"

focal_by_recorder <- focal_by_recorder[
  order(
    focal_by_recorder$`Common Name`,
    focal_by_recorder$recorder
  ),
]


# ---- 13. KIRA-positive convenience tables ----
#
# These reproduce the recorder/file audit that was used to
# confirm that recorder 2MA04668 contains no verified-positive
# KIRA segments.

kira_by_file <- focal_by_file[
  focal_by_file$`Common Name` == "King Rail" &
    focal_by_file$positive_segments > 0,
  c(
    "Begin File",
    "positive_segments"
  )
]

names(kira_by_file)[2] <-
  "positive_KIRA_segments"


kira_by_recorder <- focal_by_recorder[
  focal_by_recorder$`Common Name` == "King Rail" &
    focal_by_recorder$positive_segments > 0,
  c(
    "recorder",
    "positive_segments"
  )
]

names(kira_by_recorder)[2] <-
  "positive_KIRA_segments"


# Confirm recorder totals equal the final pilot KIRA count.

expected_kira <- focal_summary$
  pilot_positive_segments[
    focal_summary$`Common Name` ==
      "King Rail"
  ]

if (
  sum(
    kira_by_recorder$positive_KIRA_segments
  ) != expected_kira
) {
  
  stop(
    "KIRA recorder summary does not equal pilot-positive KIRA total."
  )
}


# ---- 14. Save permanent audit outputs ----

segment_eligibility_summary <- data.frame(
  metric = c(
    "raw_done1_parent_segments",
    "excluded_done1_parent_segments",
    "pilot_includable_done1_parent_segments",
    "background_segments"
  ),
  
  count = c(
    nrow(raw_done1_parents),
    nrow(excluded_parents),
    nrow(includable_parents),
    nrow(background_unique)
  )
)


write.csv(
  focal_summary,
  "output/qc/01_focal_segment_summary.csv",
  row.names = FALSE
)

write.csv(
  segment_eligibility_summary,
  "output/qc/01_segment_eligibility_summary.csv",
  row.names = FALSE
)

write.csv(
  focal_by_file,
  "output/qc/01_focal_segments_by_file.csv",
  row.names = FALSE
)

write.csv(
  focal_by_recorder,
  "output/qc/01_focal_segments_by_recorder.csv",
  row.names = FALSE
)

write.csv(
  kira_by_file,
  "output/qc/01_KIRA_positive_by_file.csv",
  row.names = FALSE
)

write.csv(
  kira_by_recorder,
  "output/qc/01_KIRA_positive_by_recorder.csv",
  row.names = FALSE
)


# ---- 15. Print audit results ----

cat(
  "\n================ FOCAL SEGMENT AUDIT ================\n"
)

print(
  focal_summary,
  row.names = FALSE
)

cat(
  "\nParent-segment eligibility:\n"
)

print(
  segment_eligibility_summary,
  row.names = FALSE
)

cat(
  "\nPilot-positive KIRA by file:\n"
)

print(
  kira_by_file,
  row.names = FALSE
)

cat(
  "\nPilot-positive KIRA by recorder:\n"
)

print(
  kira_by_recorder,
  row.names = FALSE
)

cat(
  "\nAudit outputs written to output/qc/\n"
)

cat(
  "=====================================================\n"
)