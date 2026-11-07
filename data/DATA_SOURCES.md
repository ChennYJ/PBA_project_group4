# Data Sources

## Crash data

We use the National Police Agency (NPA) nationwide case-level crash records from the Government Open Data Platform (data.gov.tw). County police department datasets are not used: most are aggregated tables, and their formats differ by county.

| Year (ROC) | Dataset | Files to download |
| --- | --- | --- |
| 2021 (110) | [歷史交通事故資料](https://data.gov.tw/dataset/12197) | 110年度A2類交通事故資料 (110年1月-6月) and (110年7月-12月) |
| 2022 (111) | [111年傷亡道路交通事故資料](https://data.gov.tw/dataset/161199) | All files |
| 2023 (112) | [112年傷亡道路交通事故資料](https://data.gov.tw/dataset/167905) | All files |
| 2024 (113) | [113年傷亡道路交通事故資料](https://data.gov.tw/dataset/172969) | All files |

Save all files in `data/raw/`. Team copy: *[Google Drive link — to be added]*

### Format notes

- **2021 (old format):** 6 columns only (`發生時間`, `發生地點`, `死亡受傷人數`, `車種`, `經度`, `緯度`). One row per crash; all vehicles are listed in `車種`, separated by `;` (e.g. `自用-小客車;普通重型-機車`). Date and time are one text field, e.g. `110年01月01日 00時02分38秒`.
- **2022+ (new format):** About 50 columns. One row per party (`當事者順位`), so a crash with two vehicles has two rows; rows must be collapsed to one row per crash. A2 files are split by month.
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

## Why A2 crashes

| Class | Definition |
| --- | --- |
| A1 | A crash causing death on the spot or within 24 hours |
| A2 | A crash causing injury, or death after 24 hours |

We use A2 crashes because of sample size. A1 crashes number only a few thousand per year nationwide, so most county-days would have zero, leaving too little variation to detect a change after TPASS. A2 crashes number in the hundreds of thousands per year, giving meaningful daily counts in every county.

**Open decision:** We could use A1 + A2 (all casualty crashes) instead. A1 adds few cases but makes the outcome definition complete. The 2022+ files already include A1; for 2021, we would also download 110年度A1類交通事故資料.

## Population data

County resident population, 2021–2024, from the Ministry of the Interior, Department of Household Registration. Saved as `data/reference/population.csv` with columns `county, year, pop`.
