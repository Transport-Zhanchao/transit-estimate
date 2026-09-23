# Add the two scenario travel times to the slim trip table.
#
# Input : data/transit_simple.csv              (one row per trip)
#         data/transit_traveltime_cut.csv
#         data/transit_traveltime_restore.csv
#         data/transit_traveltime_sampled_cut.csv
#         data/transit_traveltime_sampled_restore.csv
# Output: data/transit_simple_estimates.csv    (the same table, plus estimates)
#
# tt_cut_min / tt_restore_min are routed once, at the reported departure time.
# tt_cut_mean_min / tt_restore_mean_min average eight departures spanning the
# reported time +/- 30 minutes, which takes most of the headway luck out of a
# single draw; tt_*_n_ok says how many of the eight actually routed.
#
# NA in either column means the trip could not be routed under that scenario;
# the reason is in the gtfs_status column of the corresponding scenario file.

suppressPackageStartupMessages(library(data.table))

trips <- fread("data/transit_simple.csv")
cut   <- fread("data/transit_traveltime_cut.csv")[,     .(record_id, tt_cut_min     = gtfs_total_min)]
rest  <- fread("data/transit_traveltime_restore.csv")[, .(record_id, tt_restore_min = gtfs_total_min)]

samp_c <- fread("data/transit_traveltime_sampled_cut.csv")[
  , .(record_id, tt_cut_mean_min = tt_mean_min, tt_cut_sd_min = tt_sd_min, tt_cut_n_ok = n_ok)]
samp_r <- fread("data/transit_traveltime_sampled_restore.csv")[
  , .(record_id, tt_restore_mean_min = tt_mean_min, tt_restore_sd_min = tt_sd_min,
      tt_restore_n_ok = n_ok)]

out <- merge(trips, cut,    by = "record_id", all.x = TRUE, sort = FALSE)
out <- merge(out,   rest,   by = "record_id", all.x = TRUE, sort = FALSE)
out <- merge(out,   samp_c, by = "record_id", all.x = TRUE, sort = FALSE)
out <- merge(out,   samp_r, by = "record_id", all.x = TRUE, sort = FALSE)

fwrite(out, "data/transit_simple_estimates.csv")

cat("rows:", nrow(out), " cols:", ncol(out), "\n")
cat("columns:", paste(names(out), collapse = ", "), "\n")
cat("estimated under cut    :", sum(!is.na(out$tt_cut_min)), "\n")
cat("estimated under restore:", sum(!is.na(out$tt_restore_min)), "\n")
cat("estimated under both   :", sum(!is.na(out$tt_cut_min) & !is.na(out$tt_restore_min)), "\n")
cat("8-draw mean, both      :",
    sum(!is.na(out$tt_cut_mean_min) & !is.na(out$tt_restore_mean_min)), "\n")

# ---- Regional Rail trips ------------------------------------------------------
# Same columns, for the trips pulled out by extract-regional-rail.R and routed on
# the merged bus + rail feeds (2025-11-05, 8-draw means).
rail_cut <- "data/transit_traveltime_sampled_rail_cut.csv"
rail_res <- "data/transit_traveltime_sampled_rail_restore.csv"
if (file.exists(rail_cut) && file.exists(rail_res)) {
  rail <- fread("data/transit_regional_rail.csv")
  rc <- fread(rail_cut)[, .(record_id, tt_cut_mean_min = tt_mean_min,
                            tt_cut_sd_min = tt_sd_min, tt_cut_n_ok = n_ok)]
  rr <- fread(rail_res)[, .(record_id, tt_restore_mean_min = tt_mean_min,
                            tt_restore_sd_min = tt_sd_min, tt_restore_n_ok = n_ok)]
  rail <- merge(rail, rc, by = "record_id", all.x = TRUE, sort = FALSE)
  rail <- merge(rail, rr, by = "record_id", all.x = TRUE, sort = FALSE)
  fwrite(rail, "data/transit_regional_rail_estimates.csv")
  cat("\nregional rail rows:", nrow(rail), " 8-draw mean, both:",
      sum(!is.na(rail$tt_cut_mean_min) & !is.na(rail$tt_restore_mean_min)), "\n")
}
