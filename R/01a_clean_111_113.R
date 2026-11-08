# 01a_clean_111_113.R
# Clean 2022–2024 (ROC 111–113) A2 crash data (new format)
#
# Input :
#   data/raw/111/
#   data/raw/112/
#   data/raw/113/
#
# Raw data:
#   one row per party（當事者）
#
# Output:
#   data/intermediate/crashes_111_113.rds
#
# Final data:
#   one row per crash
#   columns: crash_id, date, hour, county, moto
#
# crash_id format:
#   111_1, 111_2, ...
#   112_1, 112_2, ...
#   113_1, 113_2, ...
#
# Agreed with 01b_clean_110.R


library(tidyverse)
library(lubridate)


# -----------------------------------------------------------
# 1. Find all A2 files from ROC 111–113
# -----------------------------------------------------------

raw_path <- "data/raw"

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
  unlist() |>
  sort()


# Check files found
cat("Number of A2 files:", length(raw_files), "\n")
print(basename(raw_files))

stopifnot(length(raw_files) > 0)


# -----------------------------------------------------------
# 2. Read and combine all A2 files
# -----------------------------------------------------------

# Read every column as text to avoid type-guessing problems
raw <- map_dfr(
  raw_files,
  function(f) {
    read_csv(
      f,
      col_types = cols(.default = col_character()),
      locale = locale(encoding = "UTF-8"),
      show_col_types = FALSE
    )
  }
)

cat("Raw rows:", nrow(raw), "\n")


# -----------------------------------------------------------
# 3. Keep actual A2 party records
# -----------------------------------------------------------

# Raw files contain footer / metadata rows.
# Actual accident records have 事故類別名稱 == "A2".

raw <- raw |>
  filter(事故類別名稱 == "A2")

cat("A2 party rows:", nrow(raw), "\n")


# -----------------------------------------------------------
# 4. Rename variables used in cleaning
# -----------------------------------------------------------

col_map <- c(
  date_raw = "發生日期",
  time_raw = "發生時間",
  place    = "發生地點",
  vehicle  = "當事者區分-類別-大類別名稱-車種",
  lon      = "經度",
  lat      = "緯度"
)

parties <- raw |>
  rename(all_of(col_map))


# -----------------------------------------------------------
# 5. Parse date, hour, county, and party rank
# -----------------------------------------------------------

parties <- parties |>
  mutate(

    # 20220101 -> 2022-01-01
    date = ymd(date_raw),

    # Ensure time is always HHMMSS
    # Example: 73000 -> 073000
    time_raw = str_pad(
      time_raw,
      width = 6,
      pad = "0"
    ),

    # Extract hour
    # Example: 073000 -> 7
    hour = as.integer(
      str_sub(time_raw, 1, 2)
    ),

    # Standardize 台 -> 臺
    place = str_replace_all(
      place,
      "台",
      "臺"
    ),

    # First three characters are county / city
    # Example: 臺北市信義區... -> 臺北市
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


# -----------------------------------------------------------
# 6. Remove exact duplicate party rows
# -----------------------------------------------------------

rows_before <- nrow(parties)

parties_clean <- parties |>
  distinct()

rows_after <- nrow(parties_clean)

cat(
  "Exact duplicate rows removed:",
  rows_before - rows_after,
  "\n"
)


# -----------------------------------------------------------
# 7. Create a base crash identifier
# -----------------------------------------------------------

# New-format data are one row per party and do not contain
# a directly usable crash ID.
#
# First identify crashes using:
# date + time + place + longitude + latitude

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


# -----------------------------------------------------------
# 8. Separate crashes sharing the same base identifier
# -----------------------------------------------------------

# Normally one crash has party ranks such as:
#
#   1, 2
#   1, 2, 3
#   1, 2, 3, 4
#
# During QA, a small number of different crashes were found
# to share the same date, time, place, longitude, and latitude.
#
# Example:
#
#   1, 2, 1, 2
#
# A new party_rank == 1 therefore marks the beginning of
# another crash within the same crash_base.

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


# All crash groups should start with party rank 1
stopifnot(
  all(parties_clean$crash_seq >= 1)
)


# Internal ID used only during data cleaning
parties_clean <- parties_clean |>
  mutate(
    internal_crash_id = paste(
      crash_base,
      crash_seq,
      sep = "_"
    )
  )


# -----------------------------------------------------------
# 9. QA: check party structure within crashes
# -----------------------------------------------------------

crash_check <- parties_clean |>
  group_by(internal_crash_id) |>
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


# QA during cleaning found only two exceptional crashes remaining.
# Both contained exactly one rank-1 party, so they are retained
# as single crashes rather than split further.


# -----------------------------------------------------------
# 10. Collapse party-level rows into crash-level rows
# -----------------------------------------------------------

# A crash is classified as a motorcycle crash if
# ANY party in that crash is classified as "機車".

crashes <- parties_clean |>
  group_by(
    internal_crash_id,
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


# -----------------------------------------------------------
# 11. Create agreed final crash_id
# -----------------------------------------------------------

# Final crash_id format follows 01b:
#
# 110 data:
#   110_1
#   110_2
#
# 111–113 data:
#   111_1
#   111_2
#   ...
#   112_1
#   ...
#   113_1
#
# date remains Gregorian, e.g. 2022-01-01.

crashes <- crashes |>
  mutate(
    roc_year = year(date) - 1911
  ) |>
  arrange(
    roc_year,
    date,
    hour,
    county,
    internal_crash_id
  ) |>
  group_by(roc_year) |>
  mutate(
    crash_id = paste0(
      roc_year,
      "_",
      row_number()
    )
  ) |>
  ungroup() |>
  select(
    crash_id,
    date,
    hour,
    county,
    moto
  )


# -----------------------------------------------------------
# 12. Final checks
# -----------------------------------------------------------

cat("\n===== FINAL DATA CHECK =====\n")


# Final structure
glimpse(crashes)


# Number of crashes
cat(
  "Total crashes:",
  nrow(crashes),
  "\n"
)


# Every crash_id must be unique
cat(
  "Unique crash IDs:",
  n_distinct(crashes$crash_id),
  "\n"
)

stopifnot(
  n_distinct(crashes$crash_id) ==
    nrow(crashes)
)


# Date range
cat(
  "Date range:",
  as.character(min(crashes$date, na.rm = TRUE)),
  "to",
  as.character(max(crashes$date, na.rm = TRUE)),
  "\n"
)


# Missing dates
cat(
  "Missing dates:",
  sum(is.na(crashes$date)),
  "\n"
)


# Hour range
cat(
  "Hour range:",
  min(crashes$hour, na.rm = TRUE),
  "to",
  max(crashes$hour, na.rm = TRUE),
  "\n"
)


# Invalid / missing hours
cat(
  "Missing hours:",
  sum(is.na(crashes$hour)),
  "\n"
)

cat(
  "Hours outside 0–23:",
  sum(
    !is.na(crashes$hour) &
      !crashes$hour %in% 0:23
  ),
  "\n"
)


# Check crashes by year
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


# moto should have no NA
cat(
  "Missing moto:",
  sum(is.na(crashes$moto)),
  "\n"
)


# Check that crash_id ROC year agrees with date
stopifnot(
  all(
    str_extract(
      crashes$crash_id,
      "^\\d+"
    ) ==
      as.character(
        year(crashes$date) - 1911
      )
  )
)


# Confirm final column names
stopifnot(
  identical(
    names(crashes),
    c(
      "crash_id",
      "date",
      "hour",
      "county",
      "moto"
    )
  )
)


# -----------------------------------------------------------
# 13. Save final RDS
# -----------------------------------------------------------

dir.create(
  "data/intermediate",
  showWarnings = FALSE,
  recursive = TRUE
)

write_rds(
  crashes,
  "data/intermediate/crashes_111_113.rds"
)

cat(
  "\nSaved to:",
  "data/intermediate/crashes_111_113.rds",
  "\n"
)
