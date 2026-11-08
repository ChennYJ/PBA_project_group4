# 00_inspect_raw.R
# Inspect raw A2 crash files before cleaning

library(tidyverse)

# ---- 1. 2022-2024 (new format): are all monthly files identical? ----

# Reference: column names of the Jan 2022 file
cols_111 <- names(read_csv("data/raw/111/A2_111_01.csv",
                           n_max = 0, show_col_types = FALSE))
length(cols_111)   # 51 columns

# List every A2 monthly file for 2022-2024
files_new <- list.files("data/raw",
                        pattern = "^A2_11[1-3]_[0-9]{2}\\.csv$",
                        recursive = TRUE, full.names = TRUE)
length(files_new)  # should be 36 (3 years x 12 months)

# For each file, read its header and compare with cols_111
same_as_111 <- map_lgl(files_new, function(f) {
  identical(names(read_csv(f, n_max = 0, show_col_types = FALSE)), cols_111)
})

all(same_as_111)          # TRUE = all 36 files have the same columns
files_new[!same_as_111]   # files that differ (character(0) = none)

# Result (2026-11-08): all 36 files share the same 51 columns

# ---- 2. 2021 (old format): what does it look like? ----

# Read the first 2000 rows of the 2021 (Jan-Jun) file
# col_types = all text, so R does not guess types wrongly
old <- read_csv("data/raw/110/A2_110_H1.csv",
                n_max = 2000,
                col_types = cols(.default = "c"))

names(old)   # column names
head(old)    # first 6 rows

# Split multi-vehicle cells ("A;B") into one row per vehicle, then count
old |>
  separate_longer_delim(車種, delim = ";") |>
  count(車種, sort = TRUE) |>
  print(n = 50)

# Result (2026-11-08):
# - 6 columns; one row per crash; date is text like "110年01月01日 00時02分38秒"
# - 車種 lists all parties separated by ";", each as "subcategory-category"
#   (e.g. "普通重型-機車"); the part after "-" = new format's major category
# - Motorcycle = any party containing "-機車"
# - E-bikes ("電動自行車-慢車") are 慢車, not 機車

# ---- 3. 2022+ (new format): vehicle categories and missing values ----

# Read the first 2000 rows of the Jan 2022 file
new_fmt <- read_csv("data/raw/111/A2_111_01.csv",
                    n_max = 2000,
                    col_types = cols(.default = "c"))

# Values of the major vehicle category
count(new_fmt, `當事者區分-類別-大類別名稱-車種`, sort = TRUE)

# Which party positions have a missing vehicle category?
new_fmt |>
  filter(is.na(`當事者區分-類別-大類別名稱-車種`)) |>
  count(當事者順位)

# Crashes whose 1st party has a missing vehicle category
# (a crash is identified by date + time + location)
na_first <- new_fmt |>
  filter(當事者順位 == "1",
         is.na(`當事者區分-類別-大類別名稱-車種`)) |>
  distinct(發生日期, 發生時間, 發生地點)

nrow(na_first)   # number of such crashes

# All parties of those crashes
new_fmt |>
  semi_join(na_first, by = c("發生日期", "發生時間", "發生地點")) |>
  select(發生日期, 發生時間, 當事者順位,
         `當事者區分-類別-大類別名稱-車種`) |>
  arrange(發生日期, 發生時間, 當事者順位) |>
  print(n = 50)

# Result (2026-11-08):
# - Major categories match the old format (機車, 小客車, 人, 慢車, ...)
# - 116 of 2000 rows have NA category; 11 of them are 1st parties
# - All 11 crashes still have other parties with a known vehicle type
#   (10 of them include a motorcycle) -> likely hit-and-run, 1st party unknown
# - Impact: negligible; at most a few motorcycle crashes are missed