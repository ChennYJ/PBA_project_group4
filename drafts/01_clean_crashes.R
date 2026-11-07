# ===========================================================
# DRAFT - reference only. Do not run as-is.
# Written before the raw data were downloaded: file paths and
# column names do not match data/raw/ yet. The final version
# will live in R/.
# ===========================================================

# 01_clean_crashes.R
# Input : data/raw/*.csv (NPA A2 crash files, one row per party 當事者)
# Output: data/intermediate/crashes.rds (one row per crash)

library(tidyverse)

# ---- 1. Read all raw files as text (avoids type-guessing errors) ----
raw_files <- list.files("data/raw", pattern = "\\.csv$", full.names = TRUE)
stopifnot(length(raw_files) > 0)

raw <- map_dfr(
  raw_files,
  ~ read_csv(.x,
             col_types = cols(.default = col_character()),
             locale = locale(encoding = "UTF-8"))  # garbled text? change to "Big5"
)

# ---- 2. Check column names, then edit the mapping below to match ----
print(names(raw))

col_map <- c(
  date_raw = "發生日期",                        # e.g. 20230701
  time_raw = "發生時間",                        # e.g. 073000 (HHMMSS)
  place    = "發生地點",                        # starts with county name
  vehicle  = "當事者區分-類別-大類別名稱-車種",   # "機車" = motorcycle
  lon      = "經度",
  lat      = "緯度"
)

# ---- 3. Clean party-level rows ----
parties <- raw |>
  rename(all_of(col_map)) |>
  mutate(
    date     = ymd(date_raw),
    time_raw = str_pad(time_raw, 6, pad = "0"),
    hour     = as.integer(str_sub(time_raw, 1, 2)),
    place    = str_replace_all(place, "台", "臺"),
    county   = str_sub(place, 1, 3)
  )

# ---- 4. Collapse parties into crashes ----
# No official crash ID, so build one from date + time + place + coordinates
crashes <- parties |>
  mutate(crash_id = paste(date_raw, time_raw, place, lon, lat, sep = "_")) |>
  group_by(crash_id, date, hour, county) |>
  summarise(
    n_parties = n(),
    moto      = any(vehicle == "機車", na.rm = TRUE),
    .groups   = "drop"
  )

# ---- 5. Sanity checks ----
cat("Party rows:", nrow(parties), "\n")
cat("Crashes   :", nrow(crashes), "\n")
cat("Missing dates:", sum(is.na(crashes$date)), "\n")
cat("Hours outside 0-23:", sum(!crashes$hour %in% 0:23), "\n")
print(count(crashes, county, sort = TRUE), n = 30)   # county names look right?
print(count(crashes, year = year(date)))             # each year present?

dir.create("data/intermediate", showWarnings = FALSE, recursive = TRUE)
write_rds(crashes, "data/intermediate/crashes.rds")
