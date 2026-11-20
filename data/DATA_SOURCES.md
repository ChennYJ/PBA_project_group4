# Data Sources

## Crash data

We use the National Police Agency (NPA) nationwide case-level crash records from the Government Open Data Platform (data.gov.tw). County police department datasets are not used: most are aggregated tables, and their formats differ by county.

We use both A1 and A2 crashes (see [Crash classes](#crash-classes-a1-and-a2)).

| Year (ROC) | Dataset | Files to download |
| --- | --- | --- |
| 2021 (110) | [歷史交通事故資料](https://data.gov.tw/dataset/12197) | 110年度A1類交通事故資料; 110年度A2類交通事故資料 (110年1月-6月) and (110年7月-12月) |
| 2022 (111) | [111年傷亡道路交通事故資料](https://data.gov.tw/dataset/161199) | All files (A1 and A2) |
| 2023 (112) | [112年傷亡道路交通事故資料](https://data.gov.tw/dataset/167905) | All files (A1 and A2) |
| 2024 (113) | [113年傷亡道路交通事故資料](https://data.gov.tw/dataset/172969) | All files (A1 and A2) |

Save all files in `data/raw/`. Team copy: *[Google Drive link — to be added]*

### Format notes

- **2021 (old format):** 6 columns only (`發生時間`, `發生地點`, `死亡受傷人數`, `車種`, `經度`, `緯度`). One row per crash; all vehicles are listed in `車種`, separated by `;` (e.g. `自用-小客車;普通重型-機車`). Date and time are one text field, e.g. `110年01月01日 00時02分38秒`. The crash class (A1 / A2) is known only from the file name.
- **2022+ (new format):** About 50 columns. One row per party (`當事者順位`), so a crash with two vehicles has two rows; rows must be collapsed to one row per crash. The crash class is in `事故類別名稱`. A1 has one file per year; A2 files are split by month.
- **Footer rows:** Every file ends with 2 note rows (`資料提供日期：…`, `事故類別：A1類` / `A2類`). They are not data and are removed during cleaning.
- **Weather and light (2022+ only):** Not kept in the cleaned data. They are missing in 2021, and NPA changed both codings on 2023-07-01 (the TPASS launch date), so light is not comparable before vs. after TPASS. Use CWA station data for weather controls instead.
- The two formats must be harmonized before merging.

### File naming in `data/raw/`

Files were renamed from the original Chinese names:

```
data/raw/
├── 110/  A1_110.csv, A2_110_H1.csv (Jan–Jun), A2_110_H2.csv (Jul–Dec)
├── 111/  A1_111.csv, A2_111_01.csv … A2_111_12.csv (by month), _meta/
├── 112/  same as 111
└── 113/  same as 111
```

`_meta/` holds the download platform's file lists; they are not data.

## Crash classes: A1 and A2

| Class | Definition |
| --- | --- |
| A1 | A crash causing death on the spot or within 24 hours |
| A2 | A crash causing injury, or death after 24 hours |

A1 + A2 together are all police-recorded casualty crashes. They do not include A3 (property damage only).

The cleaned crash data keep both classes, with a `class` column (`A1` / `A2`). The panel provides two outcomes:

| Outcome | Columns in `panel_daily.csv` | Use |
| --- | --- | --- |
| A2 only | `n_moto`, `moto_crash_rate` (+ `_rush`) | Original specification in the proposal |
| A1 + A2 | `n_moto_a1a2`, `moto_crash_rate_a1a2` (+ `_rush_a1a2`) | Complete casualty-crash definition |

A1 alone is too rare for daily county counts (a few thousand per year nationwide, so most county-days are zero), so it is not used as a separate daily outcome.

## Population data

County resident population, 2021–2024, from the Ministry of the Interior, Department of Household Registration. Saved as `data/reference/population.csv` with columns `county, year, pop`.

## T3: Calendar, closures and weather

All three tables use the same keys as `panel_daily.csv` (`county` in Traditional Chinese, e.g. 臺北市; `date` as YYYY-MM-DD), so they join with `left_join(by = c("county", "date"))` (calendar: `by = "date"`). Scripts: `R/04a_build_calendar.R`, `R/04b_build_closures.R`, `R/04c_build_weather.R` (run after 02, any order). Raw files are small and are kept on GitHub (see `.gitignore`).

### Government office calendar → `data/reference/calendar_2021_2024.csv`

| Item | Detail |
| --- | --- |
| Source | DGPA 中華民國政府行政機關辦公日曆表, [data.gov.tw/dataset/14718](https://data.gov.tw/dataset/14718): general CSVs for 110–113 (not the Google Calendar versions; no revised versions exist for these years) |
| Raw | `data/raw/calendar/dgpa_calendar_110.csv` … `_113.csv` (columns 西元日期, 星期, 是否放假, 備註; official code 0 = office open, 2 = closed) |
| Rows | 1,461 days (2021-01-01 to 2024-12-31) |
| Key columns | `workday`, `makeup_workday` (補行上班 Saturdays), `weekday_holiday`, `holiday_name`, `holiday_type`, `rush_day_workday` (DGPA workday), `rush_day_monfri` (plain Mon–Fri, the proposal's definition) |

The office calendar is a proxy for commuting days; it does not describe private-sector shift schedules. Raw files were checked against the official CSVs row by row (row counts, holiday counts and a date checksum match for all four years).

### Natural-disaster closures → `data/reference/closures_daily.csv`

| Item | Detail |
| --- | --- |
| Source | DGPA [歷次天然災害停止上班上課訊息](https://www.dgpa.gov.tw/informationlist?uid=374): every archive page dated 2021-01-01 to 2024-12-31 (145 pages; each page's `nds.html` attachment is the day's final county table) |
| Raw | `data/raw/closures/dgpa_closure_notices_2021_2024.csv` (study-county text as published, with page id, update time and source URL); `dgpa_closure_pages_2021_2024.csv` (all 145 pages) |
| Rows | 10 counties × 1,461 days = 14,610 |
| Key columns | `work_closure`, `school_closure` (county-wide only), `closure_fullday`, `closure_timing` (full / am / pm / evening / from_HH:MM), `std_reached` (已達停止上班及上課標準, used on non-workdays), `partial_work_closure`, `partial_school_closure`, `partial_area`, `source_url`, `notice_text` |
| Audit file | `data/reference/closure_statements.csv`: every statement with its parsed codes |

Coding rules: the date is the actual closure date, not the publication date. A district, village or school closure is recorded only in `partial_*` and is never coded as a county-wide closure. Days without a DGPA page are coded 0 (no closure announced); the DGPA archive is the national record, but a purely local notice that never reached DGPA would be missed. Non-typhoon events (heavy rain, earthquakes) are included because the archive covers all natural disasters.

County-wide closure days in the study counties: 2021: 3 dates (all weekends, 已達標準); 2022: none; 2023: 7 dates (Doksuri, Khanun, Haikui, Koinu); 2024: 9 dates (Gaemi, Krathon, Kong-rey).

### Weather → `data/clean/weather_daily.csv`

| Item | Detail |
| --- | --- |
| Source | CWA [CODiS](https://codis.cwa.gov.tw/StationData) daily station report (日報表), retrieved 2026-11-20 |
| Raw | `data/raw/weather/codis_daily_2021_2024.csv` (values exactly as CODiS returns them, 20 stations, 2021–2024); `codis_station_candidates.csv` (8 nearest stations per county with start/end dates and CWA remarks) |
| Station table | `data/reference/weather_station_map.csv` (primary + alternate per county, reason, closer stations rejected and why) |
| Coverage table | `data/reference/weather_coverage.csv` (missing %, trace days, partial days, primary–alternate correlation) |
| Rows | 10 counties × 1,430 days = 14,300 (same as the panel) |
| Key columns | `temp_c` (daily mean °C), `rain_mm` (daily total), `rain_trace`, `wind_ms`, `*_missing_hours`; `temp_c_alt`, `rain_mm_alt`; `temp_c_filled`, `rain_mm_filled` with `*_filled_from_alt` flags |

Station rule (fixed before looking at crash data): eligible stations are CWA manned stations or automatic weather stations (C0…) that ran under one station ID for the whole study period, below 300 m. Primary = a manned station within 10 km of the county hall if one exists, otherwise the eligible station nearest the county hall. Alternate = next-nearest eligible station.

| County | Primary | Alternate | Why not the obvious station |
| --- | --- | --- | --- |
| 基隆市 | 466940 基隆 (manned) | C0B010 七堵 | — |
| 臺北市 | 466920 臺北 (manned) | C0AC70 信義 | — |
| 新北市 | C0AH10 永和 | C0ACA0 新莊 | 板橋 manned station moved to 新店 on 2023-01-01 |
| 桃園市 | C0C480 桃園 | C0C700 中壢 | 新屋 manned station is on the coast |
| 苗栗縣 | C0E750 苗栗 | C0E870 高鐵苗栗 | 後龍 manned station opened 2024-05 |
| 彰化縣 | C0G910 花壇 | C0G780 秀水 | No station in 彰化市; 田中 manned station is about 23 km away |
| 南投縣 | C0I460 南投 | C0I410 名間 | 日月潭 is at 1,017 m |
| 臺南市 | 467410 臺南 (manned) | C0X100 臺南市北區 | — |
| 高雄市 | C0V490 新興 | C0V710 苓雅 | 高雄 manned station moved to 楠梓 on 2022-01-24 |
| 屏東縣 | C0R570 麟洛 | C0R480 長治 | 恆春 is at the southern tip; C0R170 屏東 closed 2024-11-02 |

Value rules: CODiS codes below −50 (−99.5, −99.7, −9999.5, −9999.6: instrument failure or no observation) → NA; rain −9.8 = trace (<0.1 mm) → `rain_mm` = 0 with `rain_trace` = 1 (manned stations only report trace); a daily value built from more than 6 missing hourly records → NA. Missing is never treated as no rain. Primary-station missing rates are 0–4% (highest: 彰化 花壇, 4%, mostly April–August 2024); after filling from the alternate station no county-day is missing. Primary and alternate daily temperatures correlate at 0.99+; rainfall at 0.80–0.98.

### Not done yet

- `school_calendar.csv` (local school calendars around the 2023 cut point): not collected. If needed, use a common summer-break definition and state it as a limitation.
