# 01b_clean_110.R
# Clean 2021 (ROC 110) A2 crash data (old format)
# Input : data/raw/110/A2_110_H1.csv, A2_110_H2.csv (one row per crash)
# Output: data/intermediate/crashes_110.rds (one row per crash)
#         columns: crash_id, date, hour, county, moto (agreed with 01a)

library(tidyverse)

# ---- 1. Read and combine both half-year files ----

files_110 <- c("data/raw/110/A2_110_H1.csv",
               "data/raw/110/A2_110_H2.csv")

# Read every column as text; bind the two files into one table
raw_110 <- map_dfr(files_110, function(f) {
  read_csv(f, col_types = cols(.default = "c"))
})

nrow(raw_110)    # total number of crashes in 2021
names(raw_110)   # should be the same 6 columns as before

# ---- 2. Parse date and hour from "110年01月01日 00時02分38秒" ----

# Extract year, month, day, hour with a regular expression
parts <- str_match(raw_110$發生時間, "(\\d+)年(\\d+)月(\\d+)日 (\\d+)時")

# Build a new table (keep raw_110 untouched)
crashes_110 <- raw_110 |>
  mutate(
    date = make_date(as.integer(parts[, 2]) + 1911,   # ROC year -> AD year
                     as.integer(parts[, 3]),          # month
                     as.integer(parts[, 4])),         # day
    hour = as.integer(parts[, 5])
  ) |>
  # Drop footer notes at the end of each file
  # (e.g. "資料提供日期：111年07月01日", "事故類別：A2類")
  filter(!is.na(date))

# Check: exactly 4 footer rows removed (2 per file)
nrow(raw_110) - nrow(crashes_110)   # should be 4

# Check: date range and hour range
range(crashes_110$date)   # should be 2021-01-01 to 2021-12-31
range(crashes_110$hour)   # should be 0 to 23

# ---- 3. County: first 3 characters of the location ----

crashes_110 <- crashes_110 |>
  mutate(county = str_sub(str_replace_all(發生地點, "台", "臺"), 1, 3))

# Check: list every county and its number of crashes
count(crashes_110, county, sort = TRUE) |> print(n = 30)

# ---- 4. Motorcycle crash: any party is a motorcycle ----

# 車種 lists all parties as "subcategory-category", separated by ";"
# A crash involves a motorcycle if any party ends in "-機車"
crashes_110 <- crashes_110 |>
  mutate(moto = str_detect(車種, "-機車"))

# Check: how many crashes are / are not motorcycle crashes?
count(crashes_110, moto)

# Check: any rows with missing vehicle info?
sum(is.na(crashes_110$moto))

# ---- 5. Crash ID and final columns ----

# Old format is already one row per crash, so the row number is a unique ID
# Prefix "110_" so IDs never clash with 01a's IDs after binding in 02
crashes_110 <- crashes_110 |>
  mutate(crash_id = paste0("110_", row_number())) |>
  select(crash_id, date, hour, county, moto)

# Check: structure of the final table
glimpse(crashes_110)

# Check: every crash_id is unique (should be TRUE)
n_distinct(crashes_110$crash_id) == nrow(crashes_110)

# ---- 6. Save ----

write_rds(crashes_110, "data/intermediate/crashes_110.rds")