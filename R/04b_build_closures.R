# 04b_build_closures.R
# T3-B: natural-disaster work/school closures (停班停課), county x day
#
# Input : data/raw/closures/dgpa_closure_notices_2021_2024.csv
#           One row per (notice page, study county): the county's text on
#           the DGPA "歷次天然災害停止上班上課訊息" archive page for that date.
#           Rows whose whole text was "尚未列入警戒區。" (not in alert area) are
#           not stored; such a county had no closure that day.
#         data/raw/closures/dgpa_closure_pages_2021_2024.csv
#           One row per archive page (date, page id, last update time, URL).
#           All 145 pages dated 2021-01-01 to 2024-12-31 were collected.
# Output: data/reference/closures_daily.csv     (10 counties x 1,461 days)
#         data/reference/closure_statements.csv (every parsed statement, for audit)
#
# Coding rules
#   * The page for date D is the day's final snapshot. Its "今天" statements
#     describe D. If no page exists for D, "明天" statements on the D-1 page
#     are used instead (source = "previous_day_notice").
#   * County-wide statements (no area prefix) set work_closure / school_closure.
#     Statements for a district, village or school (text before ":") only set
#     the partial_* columns. A partial closure is never coded as county-wide.
#   * "已達停止上班及上課標準" (closure standard reached, used on non-workdays)
#     counts as a closure; std_reached = 1 marks these.
#   * "未達停止上班及上課標準", "照常上班、照常上課" and "尚未列入警戒區" are 0.
#   * Timing: full / am / pm / evening / from_HH:MM (raw text kept).
#   * Days with no DGPA page are coded 0 (no closure announced). The DGPA
#     archive is the national record of announcements, but local notices
#     that never reached DGPA would be missed.

library(tidyverse)

study_counties <- c("基隆市", "桃園市", "苗栗縣", "彰化縣", "南投縣",
                    "臺南市", "高雄市", "屏東縣", "臺北市", "新北市")

notices <- read_csv("data/raw/closures/dgpa_closure_notices_2021_2024.csv",
                    col_types = cols(.default = "c", notice_date = "D"))
pages   <- read_csv("data/raw/closures/dgpa_closure_pages_2021_2024.csv",
                    col_types = cols(.default = "c", notice_date = "D"))

stopifnot(nrow(pages) == 145, !anyDuplicated(pages$notice_date),
          all(notices$county %in% study_counties))

# ---- 1. Split each county text into statements ----
statements <- notices |>
  mutate(stmt = str_split(notice_text, "。")) |>
  unnest(stmt) |>
  mutate(stmt = str_trim(stmt)) |>
  filter(stmt != "") |>
  mutate(
    # "<area>:<今天|明天><status>"  or  "<今天|明天><status>"  or  "尚未列入警戒區"
    area   = str_match(stmt, "^(.*?):(今天|明天)")[, 2],
    day    = str_match(stmt, "(?:^|:)(今天|明天)")[, 2],
    status = str_remove(stmt, "^(.*?:)?(今天|明天)"),
    scope  = if_else(is.na(area), "county", "partial"),
    target_date = notice_date + if_else(day == "明天", 1L, 0L)
  )

# Statements without 今天/明天 must be "尚未列入警戒區" (not in alert area)
odd <- filter(statements, is.na(day))
stopifnot(all(odd$stmt == "尚未列入警戒區"))
statements <- statements |>
  mutate(day = replace_na(day, "今天"),
         target_date = if_else(is.na(target_date), notice_date, target_date))

# ---- 2. Classify each statement ----
statements <- statements |>
  mutate(
    not_reached = str_detect(status, "未達停止上班及上課標準"),
    std_reached = str_detect(status, "已達停止上班及上課標準"),
    school_only_std = str_detect(status, "未達停止上班、已達停止上課標準"),
    work = case_when(
      not_reached | school_only_std          ~ 0L,
      std_reached                            ~ 1L,
      str_detect(status, "停止上班")          ~ 1L,
      TRUE                                   ~ 0L),
    school = case_when(
      not_reached                            ~ 0L,
      std_reached | school_only_std          ~ 1L,
      str_detect(status, "停止上課")          ~ 1L,
      TRUE                                   ~ 0L),
    timing = case_when(
      work == 0 & school == 0                ~ NA_character_,
      str_detect(status, "^上午\\d")          ~ paste0("from_", str_extract(status, "\\d{2}:\\d{2}")),
      str_detect(status, "^(下午|中午)\\d")    ~ paste0("from_", str_extract(status, "\\d{2}:\\d{2}")),
      str_detect(status, "^晚上")             ~ "evening",
      str_detect(status, "^上午")             ~ "am",
      str_detect(status, "^下午")             ~ "pm",
      TRUE                                   ~ "full")
  )

# Every status must match a known phrase
known <- "停止上班|照常上班|已達停止|未達停止|尚未列入警戒區"
stopifnot(all(str_detect(statements$status, known) | statements$stmt == "尚未列入警戒區"))

# ---- 3. Pick the statements that describe each date ----
# Same-day page first; previous-day "明天" only if that date has no page
statements <- statements |>
  mutate(source = if_else(day == "今天", "same_day_notice", "previous_day_notice")) |>
  filter(source == "same_day_notice" |
           !(target_date %in% pages$notice_date))

page_url <- pages |> select(notice_date, source_url)

daily_events <- statements |>
  group_by(county, date = target_date) |>
  summarise(
    work_closure   = max(c(0L, work[scope == "county"])),
    school_closure = max(c(0L, school[scope == "county"])),
    std_reached    = as.integer(any(std_reached[scope == "county"] &
                                      (work[scope == "county"] == 1))),
    closure_timing = paste(unique(na.omit(timing[scope == "county" &
                                                 (work + school) > 0])), collapse = ";"),
    partial_work_closure   = max(c(0L, work[scope == "partial"])),
    partial_school_closure = max(c(0L, school[scope == "partial"])),
    partial_area = paste(unique(area[scope == "partial" & (work + school) > 0]),
                         collapse = "；"),
    notice_source = first(source),
    notice_page_date = first(notice_date),
    notice_text = paste(unique(stmt), collapse = "。"),
    .groups = "drop") |>
  left_join(page_url, by = c("notice_page_date" = "notice_date"))

# ---- 4. Full county x day grid ----
closures <- expand_grid(county = study_counties,
                        date   = seq(ymd("2021-01-01"), ymd("2024-12-31"), by = "day")) |>
  left_join(daily_events, by = c("county", "date")) |>
  mutate(
    across(c(work_closure, school_closure, std_reached,
             partial_work_closure, partial_school_closure), ~ replace_na(.x, 0L)),
    across(c(closure_timing, partial_area), ~ na_if(.x, "")),
    dgpa_page_exists = as.integer(date %in% pages$notice_date),
    # Simple flags for models: full-day county-wide closure
    closure_fullday = as.integer(work_closure == 1 &
                                   coalesce(closure_timing, "") == "full")
  ) |>
  select(county, date, work_closure, school_closure, closure_fullday,
         closure_timing, std_reached, partial_work_closure,
         partial_school_closure, partial_area, notice_source,
         dgpa_page_exists, source_url, notice_text)

# ---- 5. Checks ----
stopifnot(nrow(closures) == 10 * 1461, !anyDuplicated(closures[c("county", "date")]))

cat("\nCounty-wide work closures (days) by county and year:\n")
closures |>
  filter(work_closure == 1) |>
  count(county, year = year(date)) |>
  pivot_wider(names_from = year, values_from = n, values_fill = 0) |>
  print(n = Inf)

cat("\nAll county-wide closure days:\n")
closures |>
  filter(work_closure == 1 | school_closure == 1) |>
  group_by(date, closure_timing, std_reached) |>
  summarise(counties = paste(county, collapse = " "), .groups = "drop") |>
  print(n = Inf, width = 200)

write_csv(closures, "data/reference/closures_daily.csv", na = "")
write_csv(statements |> select(notice_date, county, stmt, area, day, target_date,
                               scope, work, school, timing, std_reached, source),
          "data/reference/closure_statements.csv", na = "")
cat("Saved data/reference/closures_daily.csv and closure_statements.csv\n")
