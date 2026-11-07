# ===========================================================
# DRAFT - reference only. Do not run as-is.
# Written before the raw data were downloaded: file paths and
# column names do not match data/raw/ yet. The final version
# will live in R/.
# ===========================================================

# 02_build_panel.R
# Input : data/intermediate/crashes.rds, data/reference/population.csv
# Output: data/clean/panel_daily.csv (county x day, 14,300 rows)

library(tidyverse)

treat_counties   <- c("基隆市", "桃園市", "苗栗縣", "彰化縣",
                      "南投縣", "臺南市", "高雄市", "屏東縣")
control_counties <- c("臺北市", "新北市")
study_counties   <- c(treat_counties, control_counties)

start_date  <- ymd("2021-01-01")
end_date    <- ymd("2024-11-30")
tpass_start <- ymd("2023-07-01")

crashes <- read_rds("data/intermediate/crashes.rds")
pop     <- read_csv("data/reference/population.csv", show_col_types = FALSE)

# ---- 1. Daily motorcycle crash counts ----
daily <- crashes |>
  filter(moto,
         county %in% study_counties,
         date >= start_date, date <= end_date) |>
  mutate(rush = wday(date, week_start = 1) <= 5 &      # Mon-Fri
                hour %in% c(7, 8, 17, 18)) |>          # 7-9 a.m., 5-7 p.m.
  group_by(county, date) |>
  summarise(n_moto      = n(),
            n_moto_rush = sum(rush),
            .groups     = "drop")

# ---- 2. Full grid so days with zero crashes are kept ----
panel <- expand_grid(county = study_counties,
                     date   = seq(start_date, end_date, by = "day")) |>
  left_join(daily, by = c("county", "date")) |>
  mutate(across(c(n_moto, n_moto_rush), ~ replace_na(.x, 0L)),
         year = year(date)) |>
  left_join(pop, by = c("county", "year")) |>
  mutate(
    group = if_else(county %in% treat_counties, "treatment", "control"),
    post  = as.integer(date >= tpass_start),
    treat = as.integer(group == "treatment" & post == 1),
    moto_crash_rate      = n_moto      / pop * 1e5,
    moto_crash_rate_rush = n_moto_rush / pop * 1e5
  )

# ---- 3. Checks ----
stopifnot(nrow(panel) == 14300)
if (anyNA(panel$pop)) stop("population.csv has empty cells - fill them in")
cat("Pre days :", n_distinct(panel$date[panel$post == 0]), "(expect 911)\n")
cat("Post days:", n_distinct(panel$date[panel$post == 1]), "(expect 519)\n")
print(panel |> group_by(county) |> summarise(mean_daily = mean(n_moto)))

dir.create("data/clean", showWarnings = FALSE, recursive = TRUE)
write_csv(panel, "data/clean/panel_daily.csv")
