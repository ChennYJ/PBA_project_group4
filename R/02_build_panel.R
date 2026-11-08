# 02_build_panel.R
# Build the county x day panel
#
# Input : data/intermediate/crashes_110.rds      (from 01b, 2021)
#         data/intermediate/crashes_111_113.rds  (from 01a, 2022-2024)
#         data/reference/population.csv          (mid-year population)
# Output: data/clean/panel_daily.csv              (10 counties x 1,430 days)
#
# Both 01a and 01b output: crash_id, date, hour, county, moto

library(tidyverse)

treat_counties   <- c("基隆市", "桃園市", "苗栗縣", "彰化縣",
                      "南投縣", "臺南市", "高雄市", "屏東縣")
control_counties <- c("臺北市", "新北市")
study_counties   <- c(treat_counties, control_counties)

start_date  <- ymd("2021-01-01")
end_date    <- ymd("2024-11-30")
tpass_start <- ymd("2023-07-01")

# ---- 1. Read and combine the two cleaned crash files ----
crashes <- bind_rows(
  read_rds("data/intermediate/crashes_110.rds"),
  read_rds("data/intermediate/crashes_111_113.rds")
)

pop <- read_csv("data/reference/population.csv",
                col_types = cols(county = "c", year = "i", pop = "d"))

# Check: no crash counted twice, and every study county is found
stopifnot(n_distinct(crashes$crash_id) == nrow(crashes))
missing_counties <- setdiff(study_counties, unique(crashes$county))
if (length(missing_counties) > 0) {
  stop("County names not found in crash data: ",
       paste(missing_counties, collapse = ", "))
}

# ---- 2. Daily motorcycle crash counts ----
# Rush hour = Mon-Fri, 7-9 a.m. and 5-7 p.m. (hours 7, 8, 17, 18)
daily <- crashes |>
  filter(moto,
         county %in% study_counties,
         date >= start_date, date <= end_date) |>
  mutate(rush = wday(date, week_start = 1) <= 5 &
                hour %in% c(7, 8, 17, 18)) |>
  group_by(county, date) |>
  summarise(n_moto      = n(),
            n_moto_rush = sum(rush),
            .groups     = "drop")

# ---- 3. Full grid so days with zero crashes are kept ----
panel <- expand_grid(county = study_counties,
                     date   = seq(start_date, end_date, by = "day")) |>
  left_join(daily, by = c("county", "date")) |>
  mutate(across(c(n_moto, n_moto_rush), ~ replace_na(.x, 0L)),
         year = as.integer(year(date))) |>
  left_join(pop, by = c("county", "year")) |>
  mutate(
    group = if_else(county %in% treat_counties, "treatment", "control"),
    post  = as.integer(date >= tpass_start),
    treat = as.integer(group == "treatment" & post == 1),
    moto_crash_rate      = n_moto      / pop * 1e5,
    moto_crash_rate_rush = n_moto_rush / pop * 1e5
  )

# ---- 4. Checks ----
stopifnot(nrow(panel) == 14300)
if (anyNA(panel$pop)) stop("Some county-years have no population - check population.csv")
cat("Pre days :", n_distinct(panel$date[panel$post == 0]), "(expect 911)\n")
cat("Post days:", n_distinct(panel$date[panel$post == 1]), "(expect 519)\n")
cat("County-days with zero motorcycle crashes:", sum(panel$n_moto == 0), "\n")

# Mean daily motorcycle crashes by county and year:
# a sudden jump between 2021 and 2022 in every county would point to a
# difference between the old (01b) and new (01a) formats
panel |>
  group_by(county, year) |>
  summarise(mean_daily = round(mean(n_moto), 1), .groups = "drop") |>
  pivot_wider(names_from = year, values_from = mean_daily) |>
  print()

dir.create("data/clean", showWarnings = FALSE, recursive = TRUE)
write_csv(panel, "data/clean/panel_daily.csv")
cat("Saved data/clean/panel_daily.csv\n")
