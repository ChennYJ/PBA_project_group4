# 04a_build_calendar.R
# T3-B: government office calendar (workdays, holidays, make-up workdays)
#
# Input : data/raw/calendar/dgpa_calendar_110.csv ... _113.csv
#         行政院人事行政總處「中華民國政府行政機關辦公日曆表」(general CSV,
#         not the Google Calendar version). data.gov.tw/dataset/14718
#         Official coding of 是否放假: 0 = office open, 2 = office closed.
# Output: data/reference/calendar_2021_2024.csv (one row per date, 2021-01-01 to 2024-12-31)
#
# Note: this is the government office calendar. It is a proxy for commuting
# days; it does not cover private-sector shift schedules.

library(tidyverse)

files <- sprintf("data/raw/calendar/dgpa_calendar_%d.csv", 110:113)

raw <- map(files, ~ read_csv(.x, col_types = cols(.default = "c"),
                             locale = locale(encoding = "UTF-8"))) |>
  list_rbind() |>
  rename(date_raw = 西元日期, weekday_zh = 星期, is_off = 是否放假, note = 備註)

stopifnot(all(raw$is_off %in% c("0", "2")))   # only official codes

calendar <- raw |>
  mutate(
    date     = ymd(date_raw),
    wday     = wday(date, week_start = 1),            # 1 = Mon ... 7 = Sun
    weekend  = as.integer(wday >= 6),
    workday  = as.integer(is_off == "0"),             # DGPA: office open
    makeup_workday = as.integer(workday == 1 & weekend == 1),   # 補行上班
    weekday_holiday = as.integer(workday == 0 & weekend == 0),  # Mon-Fri off
    holiday_name = if_else(is.na(note) | note == "補行上班", NA_character_, note),
    # 調整放假 / 補假 are days off created by the calendar, not festivals
    holiday_type = case_when(
      makeup_workday == 1                  ~ "makeup_workday",
      holiday_name %in% c("調整放假")       ~ "bridge_day",
      holiday_name %in% c("補假")           ~ "substitute_day",
      !is.na(holiday_name)                 ~ "national_holiday",
      weekend == 1                         ~ "weekend",
      TRUE                                 ~ "workday"
    ),
    # Two rush-hour day definitions kept side by side (see T3 spec):
    #   rush_day_workday: DGPA workday (includes make-up Saturdays, excludes holidays)
    #   rush_day_monfri : plain Mon-Fri (original proposal definition)
    rush_day_workday = workday,
    rush_day_monfri  = as.integer(weekend == 0),
    source = "DGPA office calendar (data.gov.tw/dataset/14718)"
  ) |>
  select(date, wday, weekend, workday, makeup_workday, weekday_holiday,
         holiday_name, holiday_type, rush_day_workday, rush_day_monfri,
         dgpa_is_off = is_off, dgpa_note = note, source)

# ---- Checks ----
stopifnot(nrow(calendar) == 1461,
          !anyDuplicated(calendar$date),
          all(diff(calendar$date) == 1))
# Weekday in the file must agree with the computed weekday
wk <- c("一", "二", "三", "四", "五", "六", "日")
stopifnot(all(wk[calendar$wday] == raw$weekday_zh))

calendar |>
  count(year = year(date), holiday_type) |>
  pivot_wider(names_from = holiday_type, values_from = n, values_fill = 0) |>
  print()

write_csv(calendar, "data/reference/calendar_2021_2024.csv", na = "")
cat("Saved data/reference/calendar_2021_2024.csv\n")
