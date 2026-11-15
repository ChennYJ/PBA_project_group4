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
