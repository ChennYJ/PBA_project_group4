# ===========================================================
# 01_clean_crashes.R
#
# Purpose:
#   Clean NPA A2 crash data for ROC years 111–113
#   (2022–2024).
#
# Input:
#   ~/Desktop/研究所/PBA/final/raw/
#     ├── 111/
#     ├── 112/
#     └── 113/
#
#   Raw data: one row per party（當事者）
#
# Output:
#   ~/Desktop/研究所/PBA/final/data/intermediate/
#     crashes_111_113.rds
#
#   Final data: one row per crash（事故）
#
# Final columns:
#   crash_id : character
#   date     : Date
#   hour     : integer
#   county   : character
#   moto     : logical
# ===========================================================


library(tidyverse)
library(lubridate)


# ===========================================================
# 1. Find A2 files from 111–113
# ===========================================================

raw_path <- "~/Desktop/研究所/PBA/final/raw"

year_dirs <- file.path(
  raw_path,
  c("111", "112", "113")
)

raw_files <- map(
  year_dirs,
  ~ list.files(
    .x,
    pattern = "^A2.*\\.csv$",
    full.names = TRUE,
    recursive = TRUE,
    ignore.case = TRUE
  )
) |>
  unlist()


# Check files found
cat("Number of A2 files:", length(raw_files), "\n")
print(basename(raw_files))

stopifnot(length(raw_files) > 0)


# ===========================================================
# 2. Read and combine all A2 files
# ===========================================================

raw <- map_dfr(
  raw_files,
  function(f) {

    read_csv(
      f,
      col_types = cols(
        .default = col_character()
      ),
      locale = locale(
        encoding = "UTF-8"
      ),
      show_col_types = FALSE
    )
  }
)


cat("Raw rows:", nrow(raw), "\n")


# ===========================================================
# 3. Keep actual A2 observations
# ===========================================================
#
# Raw CSVs contain some metadata rows.
#
# Actual accident rows:
#   事故類別名稱 == "A2"
#
# This removes the metadata rows where 事故類別名稱 is NA.
# ===========================================================

raw <- raw |>
  filter(事故類別名稱 == "A2")


cat("A2 party rows:", nrow(raw), "\n")


# ===========================================================
# 4. Rename variables needed for analysis
# ===========================================================

col_map <- c(
  date_raw = "發生日期",
  time_raw = "發生時間",
  place    = "發生地點",
  vehicle  = "當事者區分-類別-大類別名稱-車種",
  lon      = "經度",
  lat      = "緯度"
)


parties <- raw |>
  rename(
    all_of(col_map)
  )


# ===========================================================
# 5. Clean party-level data
# ===========================================================

parties <- parties |>
  mutate(

    # Example:
    # 20220101 -> 2022-01-01
    date = ymd(date_raw),

    # Ensure HHMMSS has six digits
    # Example:
    # 73000 -> 073000
    time_raw = str_pad(
      time_raw,
      width = 6,
      pad = "0"
    ),

    # Extract hour
    # Example:
    # 073000 -> 7
    hour = as.integer(
      str_sub(
        time_raw,
        1,
        2
      )
    ),

    # Standardize place names
    # 台北市 -> 臺北市
    place = str_replace_all(
      place,
      "台",
      "臺"
    ),

    # First three characters = county / city
    # Example:
    # 臺北市信義區... -> 臺北市
    county = str_sub(
      place,
      1,
      3
    ),

    # Party order within a crash
    party_rank = as.integer(
      `當事者順位`
    )
  )


# ===========================================================
# 6. Remove exact duplicate rows
# ===========================================================
#
# During QA, a small number of exact duplicate party rows
# were found.
# ===========================================================

rows_before <- nrow(parties)

parties_clean <- parties |>
  distinct()

rows_after <- nrow(parties_clean)

cat(
  "Exact duplicate rows removed:",
  rows_before - rows_after,
  "\n"
)


# ===========================================================
# 7. Create a base crash identifier
# ===========================================================
#
# There is no reliable official crash ID in the working data.
#
# Initial crash identity:
#   date + time + place + longitude + latitude
#
# However, QA showed that a small number of different crashes
# can share exactly the same combination.
# ===========================================================

parties_clean <- parties_clean |>
  mutate(
    crash_base = paste(
      date_raw,
      time_raw,
      place,
      lon,
      lat,
      sep = "_"
    )
  )


# ===========================================================
# 8. Separate crashes that share the same base identifier
# ===========================================================
#
# Within one crash, 當事者順位 normally looks like:
#
#   1, 2
#   1, 2, 3
#   1, 2, 3, 4
#
# If multiple crashes have the same date/time/place/coordinates:
#
#   1, 2, 1, 2
#
# each new party_rank == 1 indicates the start of another crash.
# ===========================================================

parties_clean <- parties_clean |>
  group_by(crash_base) |>
  mutate(
    crash_seq = cumsum(
      replace_na(
        party_rank == 1,
        FALSE
      )
    )
  ) |>
  ungroup()


# Final unique crash ID
parties_clean <- parties_clean |>
  mutate(
    crash_id = paste(
      crash_base,
      crash_seq,
      sep = "_"
    )
  )


# ===========================================================
# 9. QA: check party structure within crashes
# ===========================================================

crash_check <- parties_clean |>
  group_by(crash_id) |>
  summarise(
    n_rows = n(),
    n_ranks = n_distinct(party_rank),
    n_rank1 = sum(
      party_rank == 1,
      na.rm = TRUE
    ),
    .groups = "drop"
  )


problem_crashes <- crash_check |>
  filter(
    n_rows != n_ranks |
      n_rank1 != 1
  )


cat(
  "Crashes requiring review:",
  nrow(problem_crashes),
  "\n"
)

print(problem_crashes)


# In our QA, only two exceptional crashes remained.
# Both contained exactly one party_rank == 1, so they are
# retained as single crashes rather than split further.


# ===========================================================
# 10. Collapse party-level data into crash-level data
# ===========================================================
#
# moto = TRUE if ANY party in the crash is classified as 機車.
#
# vehicle NA rows are retained.
# ===========================================================

crashes <- parties_clean |>
  group_by(
    crash_id,
    date,
    hour,
    county
  ) |>
  summarise(
    moto = any(
      vehicle == "機車",
      na.rm = TRUE
    ),
    .groups = "drop"
  )


# ===========================================================
# 11. Keep only the team's required schema
# ===========================================================

crashes <- crashes |>
  select(
    crash_id,
    date,
    hour,
    county,
    moto
  )


# ===========================================================
# 12. Final sanity checks
# ===========================================================

cat("\n===== FINAL DATA CHECK =====\n")

cat(
  "Party rows:",
  nrow(parties_clean),
  "\n"
)

cat(
  "Crash rows:",
  nrow(crashes),
  "\n"
)


# Crash ID must be unique
cat(
  "Unique crash IDs:",
  n_distinct(crashes$crash_id),
  "\n"
)


# Missing dates
cat(
  "Missing dates:",
  sum(is.na(crashes$date)),
  "\n"
)


# Invalid hours
cat(
  "Invalid hours:",
  sum(
    is.na(crashes$hour) |
      !crashes$hour %in% 0:23
  ),
  "\n"
)


# Check years
print(
  crashes |>
    count(
      year = year(date)
    )
)


# Check county names
print(
  crashes |>
    count(
      county,
      sort = TRUE
    ),
  n = 30
)


# Check motorcycle indicator
print(
  crashes |>
    count(moto)
)


# Check final structure
glimpse(crashes)


# Confirm crash_id uniqueness
stopifnot(
  nrow(crashes) ==
    n_distinct(crashes$crash_id)
)


# ===========================================================
# 13. Save final RDS
# ===========================================================

output_dir <- file.path(
  raw_path,
  "..",
  "data",
  "intermediate"
)

dir.create(
  output_dir,
  showWarnings = FALSE,
  recursive = TRUE
)


output_file <- file.path(
  output_dir,
  "crashes_111_113.rds"
)


write_rds(
  crashes,
  output_file
)


cat(
  "\nSaved to:",
  output_file,
  "\n"
)
