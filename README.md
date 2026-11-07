# Did TPASS Reduce Motorcycle Crashes?

Group 4 (Fiona, Austine, Yoona) · ISS5066 PBA

## Research question

Did TPASS reduce motorcycle crashes more in counties with no prior monthly pass than in Taipei and New Taipei, which have had the 1280 pass since 2018?

We use a difference-in-differences design on a county × day panel:

| Item | Detail |
| --- | --- |
| Period | 2021-01-01 to 2024-11-30 (911 days before TPASS, 519 after) |
| TPASS launch | 2023-07-01 |
| Treatment (8) | Keelung, Taoyuan, Miaoli, Changhua, Nantou, Tainan, Kaohsiung, Pingtung |
| Control (2) | Taipei, New Taipei |
| Excluded | Taichung (prior free-bus policy; recording change in Jan 2023) |
| Panel size | 10 counties × 1,430 days = 14,300 rows |

## Repository structure

```
PBA_project_group4/
├── PBA_project_group4.Rproj   # Open this to start working in RStudio
├── README.md
├── .gitignore                 # Files Git should not upload
├── R/                         # R scripts, numbered in run order
├── data/
│   ├── raw/                   # Original A2 crash files (NOT on GitHub)
│   ├── intermediate/          # Temporary files made by scripts (NOT on GitHub)
│   ├── reference/             # Small lookup tables: population, holidays
│   └── clean/                 # Final analysis-ready panel
└── figures/                   # Plots exported by scripts
```

## Data sources

| Data | Coverage | Source | Saved as |
| --- | --- | --- | --- |
| A2 injury crash records (National Police Agency) | 2021–2024 | [data.gov.tw](https://data.gov.tw), search "A2類道路交通事故" | `data/raw/*.csv` |
| County population (Ministry of the Interior) | 10 counties, 2021–2024 | Department of Household Registration statistics | `data/reference/population.csv` |
| National holidays (for rush-hour outcome) | 2021–2024 | DGPA official office calendar | `data/reference/holidays.csv` |

Team copy of raw data: *[Google Drive link — to be added]*