# Transit Estimate
Transit estimate for septa project

## Scripts

All R scripts live in `scripts/` and are numbered in the order they run. Each
script sets the working directory to the project root with `here::here()`, so
the paths inside them (`data/`, `figures/`, `tables/`, `report/`) work no matter
where you launch them from.

| # | Script | What it does | Main output |
|---|--------|--------------|-------------|
| 01 | `01-pre-process.R` | Filters survey trips to weekday SEPTA bus / subway / trolley trips | `data/transit_simple.csv`, `data/transit_weekday_timed.csv` |
| 02 | `02-extract-regional-rail.R` | Pulls Regional Rail trips and their feeder legs | `data/transit_regional_rail.csv` |
| 03 | `03-merge-gtfs.R` | Merges the bus and rail GTFS feeds | `data/gtfs/*_merged.zip` |
| 04 | `04-estimate-traveltime.R` | Routes each trip through GTFS (set `TT_SCENARIO=cut` / `restore`) | `data/transit_traveltime_*.csv` |
| 05 | `05-join-results.R` | Joins cut / restore travel times onto the trip tables | `data/*_estimates.csv` |
| 06 | `06-make-figures.R` | Draws figures 01–04 | `figures/*.png` |
| 07 | `07-compare-rail-vs-bus.R` | Rail vs other tables and figure 05 | `tables/rail-vs-other.md` |
| 08 | `08-build-report.R` | Fills `report-template.md` and writes the trip-level csv | `report/report.md`, `report/trip-level-results.csv` |

Example:

```bash
TT_SCENARIO=cut Rscript scripts/04-estimate-traveltime.R
```
