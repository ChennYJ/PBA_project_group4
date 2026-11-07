# drafts/

Draft R scripts for team reference only. **Do not run them as-is.**

They were written before the raw data were downloaded, so they assume one folder of CSVs and the 2022+ column names. Known gaps:

- `01_clean_crashes.R` reads every CSV in `data/raw/`; it must instead read `data/raw/111–113/A2_*.csv` (new format) and handle `data/raw/110/` (old format) in a separate script.
- The 2021 (110) files use a different format; see `data/DATA_SOURCES.md`.

Final scripts go in `R/`. Delete this folder once they are done.
