# 04c_build_weather.R
# T3-A: county x day weather (temperature, rainfall, wind)
#
# Input : data/raw/weather/codis_station_candidates.csv
#           CWA CODiS station list (api/station_list, downloaded 2026-11-20):
#           the 8 stations nearest each county hall, with start/end dates.
#         data/raw/weather/codis_daily_2021_2024.csv
#           CODiS daily station report ("report_month") for the 20 selected
#           stations (primary + alternate), 2021-01-01 to 2024-12-31.
#           Values are kept exactly as CODiS returns them. *_missing_hours is
#           CODiS's per-value flag: the number of hourly records missing that
#           day (0-24); CODiS marks a value with * when it is > 0.
# Output: data/reference/weather_station_map.csv  (station chosen per county)
#         data/clean/weather_daily.csv            (10 counties x 1,430 days)
#         data/reference/weather_coverage.csv     (missing rates by station)
#
# Station rule (fixed before looking at any crash data):
#   Eligible = CWA manned station (cwb) or automatic weather station (C0...,
#   measures temperature and rain), one station ID in operation for the whole
#   study period (2021-01-01 to 2024-11-30, no relocation or code change),
#   altitude < 300 m.
#   Primary = an eligible manned station within 10 km of the county hall if
#   one exists, otherwise the eligible station nearest the county hall.
#   Alternate = the next-nearest eligible station (for sensitivity checks).
#
# Value rules:
#   * Codes below -50 (e.g. -99.5, -99.7, -9999.5, -9999.6: instrument
#     failure / no observation) -> NA. Missing is never treated as no rain.
#   * Rain -9.8 = trace (<0.1 mm, CODiS "T") -> rain_mm = 0, rain_trace = 1.
#   * A daily value built from more than 6 missing hours (>25% of the day)
#     -> NA. The raw missing-hour counts are kept so this can be changed.

library(tidyverse)

start_date <- ymd("2021-01-01")
end_date   <- ymd("2024-11-30")
max_missing_hours <- 6

# ---- 1. Choose stations ----
cand <- read_csv("data/raw/weather/codis_station_candidates.csv",
                 col_types = cols(station_id = "c", station_start = "D",
                                  station_end = "D"))

eligible <- cand |>
  filter(station_start <= start_date,
         is.na(station_end) | station_end >= end_date,
         altitude_m < 300,
         station_type == "cwb" | str_starts(station_id, "C0")) |>
  arrange(county, dist_to_county_hall_km)

primary <- eligible |>
  group_by(county) |>
  mutate(cwb_near = station_type == "cwb" & dist_to_county_hall_km <= 10) |>
  arrange(desc(cwb_near), dist_to_county_hall_km, .by_group = TRUE) |>
  slice(1) |>
  mutate(role = "primary",
         reason = if_else(cwb_near,
                          "manned station within 10 km of county hall, continuous",
                          "nearest continuous automatic station to county hall")) |>
  ungroup() |>
  select(-cwb_near)

alternate <- eligible |>
  anti_join(primary, by = "station_id") |>
  group_by(county) |>
  slice_min(dist_to_county_hall_km, n = 1, with_ties = FALSE) |>
  ungroup() |>
  mutate(role = "alternate", reason = "next-nearest continuous station")

# Stations closer than the primary that were rejected, and why
rejected <- cand |>
  left_join(select(primary, county, primary_dist = dist_to_county_hall_km), by = "county") |>
  filter(dist_to_county_hall_km < primary_dist) |>
  mutate(why = case_when(
    station_start > start_date ~ paste0("starts ", station_start),
    !is.na(station_end) & station_end < end_date ~ paste0("ends ", station_end),
    altitude_m >= 300 ~ "altitude >= 300 m",
    TRUE ~ "manned station preferred")) |>
  group_by(county) |>
  summarise(closer_stations_rejected = paste0(station_id, " ", station_name, " (", why, ")",
                                              collapse = "; "))

station_map <- bind_rows(primary, alternate) |>
  left_join(rejected, by = "county") |>
  mutate(coverage_start = pmax(station_start, start_date),
         coverage_end   = if_else(is.na(station_end), end_date, pmin(station_end, end_date))) |>
  select(county, role, station_id, station_name, station_type, altitude_m,
         longitude, latitude, dist_to_county_hall_km, station_start, station_end,
         coverage_start, coverage_end, reason, closer_stations_rejected, web_remark) |>
  arrange(county, desc(role))

stopifnot(nrow(primary) == 10, nrow(alternate) == 10)

# ---- 2. Clean daily values ----
raw <- read_csv("data/raw/weather/codis_daily_2021_2024.csv",
                col_types = cols(station_id = "c", date = "D", .default = "d"))

clean_val <- function(x, miss_h) {
  x <- if_else(!is.na(x) & x < -50, NA_real_, x)        # missing / failure codes
  if_else(!is.na(miss_h) & miss_h > max_missing_hours, NA_real_, x)
}

wx <- raw |>
  filter(date >= start_date, date <= end_date) |>
  mutate(
    rain_trace = as.integer(!is.na(rain_accum) & rain_accum == -9.8),
    rain_code_missing = as.integer(!is.na(rain_accum) & rain_accum < -50),
    rain_tmp   = if_else(rain_trace == 1, 0, rain_accum),
    temp_c     = clean_val(temp_mean, temp_mean_missing_hours),
    temp_max_c = clean_val(temp_max,  temp_mean_missing_hours),
    temp_min_c = clean_val(temp_min,  temp_mean_missing_hours),
    rain_mm    = clean_val(rain_tmp,  rain_missing_hours),
    wind_ms    = clean_val(wind_mean, wind_missing_hours)
  )

# Any other negative rain value would be an unknown code
stopifnot(all(is.na(wx$rain_tmp) | wx$rain_tmp >= 0 | wx$rain_tmp < -50))

# ---- 3. County x day table ----
pick <- function(role_name, suffix) {
  station_map |>
    filter(role == role_name) |>
    select(county, station_id) |>
    left_join(wx, by = "station_id", relationship = "one-to-many") |>
    select(county, date, station_id, temp_c, temp_max_c, temp_min_c, rain_mm,
           rain_trace, wind_ms, temp_missing_hours = temp_mean_missing_hours,
           rain_missing_hours) |>
    rename_with(~ paste0(.x, suffix), -c(county, date))
}

weather <- expand_grid(county = unique(station_map$county),
                       date = seq(start_date, end_date, by = "day")) |>
  left_join(pick("primary", ""), by = c("county", "date")) |>
  left_join(pick("alternate", "_alt") |>
              select(county, date, station_id_alt, temp_c_alt, rain_mm_alt),
            by = c("county", "date")) |>
  mutate(
    # Filled versions: primary value, alternate station when primary is NA.
    # Use temp_c / rain_mm for the main model and *_filled as a robustness
    # check, or the reverse; filled_from_alt marks every substituted day.
    temp_c_filled  = coalesce(temp_c, temp_c_alt),
    rain_mm_filled = coalesce(rain_mm, rain_mm_alt),
    temp_filled_from_alt = as.integer(is.na(temp_c) & !is.na(temp_c_alt)),
    rain_filled_from_alt = as.integer(is.na(rain_mm) & !is.na(rain_mm_alt)),
    rain_any  = as.integer(rain_mm > 0),          # NA stays NA
    rain_heavy = as.integer(rain_mm >= 80),       # CWA heavy-rain threshold (24 h)
    source = "CWA CODiS daily station report"
  )

# ---- 4. Coverage / missing report ----
coverage <- station_map |>
  select(county, role, station_id, station_name) |>
  left_join(wx, by = "station_id") |>
  group_by(county, role, station_id, station_name) |>
  summarise(
    days = n(),
    temp_na_pct = round(100 * mean(is.na(temp_c)), 2),
    rain_na_pct = round(100 * mean(is.na(rain_mm)), 2),
    rain_code_missing_days = sum(rain_code_missing),
    rain_trace_days = sum(rain_trace),
    temp_partial_days = sum(temp_mean_missing_hours > 0 &
                              temp_mean_missing_hours <= max_missing_hours, na.rm = TRUE),
    rain_partial_days = sum(rain_missing_hours > 0 &
                              rain_missing_hours <= max_missing_hours, na.rm = TRUE),
    mean_temp = round(mean(temp_c, na.rm = TRUE), 1),
    annual_rain_mm = round(mean(rain_mm, na.rm = TRUE) * 365),
    .groups = "drop") |>
  arrange(county, desc(role))

# Agreement between primary and alternate (should be high)
agree <- weather |>
  group_by(county) |>
  summarise(cor_temp = round(cor(temp_c, temp_c_alt, use = "complete.obs"), 3),
            cor_rain = round(cor(rain_mm, rain_mm_alt, use = "complete.obs"), 3),
            .groups = "drop")
coverage <- left_join(coverage, agree, by = "county")

# ---- 5. Checks ----
stopifnot(nrow(weather) == 14300,
          !anyDuplicated(weather[c("county", "date")]),
          all(!is.na(weather$station_id)))
print(select(station_map, county, role, station_id, station_name, dist_to_county_hall_km),
      n = Inf)
print(coverage, n = Inf, width = 200)

write_csv(station_map, "data/reference/weather_station_map.csv", na = "")
write_csv(coverage,    "data/reference/weather_coverage.csv", na = "")
write_csv(weather,     "data/clean/weather_daily.csv", na = "")
cat("Saved weather_station_map.csv, weather_coverage.csv, weather_daily.csv\n")
