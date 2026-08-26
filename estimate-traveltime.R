# Estimate a door-to-door transit travel time for every surveyed trip by
# routing it through the SEPTA GTFS feed, departing at the trip's own
# reported departure time.
#
# Input : data/transit_simple.csv   (one row per trip, from pre-process.R)
#         data/gtfs/<scenario>.zip  ("cut" = CLIFF service cuts, "restore" =
#                                    the regular feed)
# Output: data/transit_traveltime_<scenario>.csv
#
# Pick the scenario with the TT_SCENARIO environment variable:
#   TT_SCENARIO=cut     Rscript estimate-traveltime.R
#   TT_SCENARIO=restore Rscript estimate-traveltime.R
# Both must run on the same service date to be comparable (TT_DATE).
#
# Routing engine is gtfsrouter: a pure C++/R RAPTOR implementation, no Java and
# no street network to build, so setup is a couple of seconds instead of the
# long graph build r5r needs.

suppressPackageStartupMessages({
  library(gtfsrouter)
  library(data.table)
  library(sf)
  library(parallel)
})

# ---- settings ---------------------------------------------------------------
# Which feed to route on: "cut" (City Fall 2025-CLIFF-B, the service-cut
# scenario) or "restore" (the regular feed published 2025-09-28).
SCENARIO     <- Sys.getenv("TT_SCENARIO", "cut")
stopifnot(SCENARIO %in% c("cut", "restore"))

# 2025-10-15 is a plain Wednesday, and it is the same weekday in both feeds:
# cut.zip runs 2025-08-25 to 2026-02-21, restore.zip only starts 2025-09-28, so
# any comparison date has to sit in the overlap.
SERVICE_DATE <- as.integer(Sys.getenv("TT_DATE", "20251015"))

GTFS_ZIP     <- sprintf("data/gtfs/%s.zip", SCENARIO)
TRIPS_CSV    <- "data/transit_simple.csv"
OUT_CSV      <- sprintf("data/transit_traveltime_%s.csv", SCENARIO)
CACHE_RDS    <- sprintf("data/cache/gtfs_%s_%s_timetable.rds", SCENARIO, SERVICE_DATE)
WALK_MPS     <- 1.33       # 4.8 km/h
DETOUR       <- 1.3        # straight line -> walked distance
ACCESS_R     <- 800        # max straight-line metres from a centroid to a stop
N_ACCESS     <- 4          # access stops routed from, nearest first
TRANSFER_R   <- 400        # walking transfers between stops
DEP_WINDOW   <- 1800       # how long a trip may wait for a departure (s)
MAX_TT       <- 120 * 60   # give up beyond this in-system travel time (s)
N_CORES      <- max(1, detectCores() - 1)

# Only rows in this range are processed; set to NULL for all trips.
ROW_LIMIT <- if (nzchar(Sys.getenv("TT_ROWS"))) as.integer(Sys.getenv("TT_ROWS")) else NULL

# ---- 1. timetable -----------------------------------------------------------
# extract_gtfs + transfer table + timetable takes ~5s, but it is the same for
# every trip, so cache it.
if (file.exists(CACHE_RDS)) {
  message("loading cached timetable: ", CACHE_RDS)
  gt <- readRDS(CACHE_RDS)
} else {
  message("building timetable from ", GTFS_ZIP)
  g <- extract_gtfs(GTFS_ZIP, quiet = TRUE)
  # the feed ships without transfers.txt, so walking transfers are generated
  g <- gtfs_transfer_table(g, d_limit = TRANSFER_R, min_transfer_time = 0,
                           quiet = TRUE)
  gt <- gtfs_timetable(g, date = SERVICE_DATE, quiet = TRUE)
  dir.create(dirname(CACHE_RDS), showWarnings = FALSE, recursive = TRUE)
  saveRDS(gt, CACHE_RDS)
}

# ---- 2. stop coordinates in metres ------------------------------------------
# stops.txt still lists stops whose route was cut and that see no vehicle all
# day (about 950 of them). Keeping them would let a dead stop crowd out a live
# one when picking the nearest few, so only stops with departures are kept.
served <- unique(gt$stop_ids$stop_ids[unique(gt$timetable$departure_station)])
stops <- as.data.table(gt$stops)[!is.na(stop_lat) & !is.na(stop_lon) &
                                   stop_id %in% served,
                                 .(stop_id, stop_name, stop_lon, stop_lat)]
message(nrow(stops), " stops with service on ", SERVICE_DATE)
stop_xy <- st_coordinates(
  st_transform(st_as_sf(stops, coords = c("stop_lon", "stop_lat"), crs = 4326),
               26918)
)

# nearest stops to a point, as (stop_id, walk seconds), nearest first
near_stops <- function(lon, lat, radius = ACCESS_R, n = NULL) {
  p <- st_coordinates(st_transform(st_sfc(st_point(c(lon, lat)), crs = 4326), 26918))
  d <- sqrt((stop_xy[, 1] - p[1])^2 + (stop_xy[, 2] - p[2])^2)
  i <- which(d <= radius)
  if (!length(i)) return(NULL)
  i <- i[order(d[i])]
  if (!is.null(n)) i <- head(i, n)
  data.table(stop_id = stops$stop_id[i],
             walk    = as.integer(ceiling(d[i] * DETOUR / WALK_MPS)))
}

hms_to_s <- function(x) {
  p <- tstrsplit(as.character(x), ":", fixed = TRUE)
  as.integer(p[[1]]) * 3600L + as.integer(p[[2]]) * 60L + as.integer(p[[3]])
}

# ---- 3. one trip ------------------------------------------------------------
# Walk to each of the nearest N access stops, ride, then walk from whichever
# stop near the destination gets us there first. Everything is measured from
# the trip's reported departure time, so the total includes access walk, the
# wait for the first vehicle, riding, transfers, and the egress walk.
estimate_one <- function(depart_lon, depart_lat, dest_lon, dest_lat, t0) {
  acc <- near_stops(depart_lon, depart_lat, ACCESS_R, N_ACCESS)
  egr <- near_stops(dest_lon,   dest_lat,   ACCESS_R)
  if (is.null(acc)) return(list(status = "no_origin_stop"))
  if (is.null(egr)) return(list(status = "no_dest_stop"))

  best <- NULL
  for (k in seq_len(nrow(acc))) {
    board_from <- t0 + acc$walk[k]
    tt <- tryCatch(
      gtfs_traveltimes(gt, from = acc$stop_id[k], from_is_id = TRUE,
                       start_time_limits = c(board_from, board_from + DEP_WINDOW),
                       max_traveltime = MAX_TT, quiet = TRUE),
      error = function(e) NULL
    )
    if (is.null(tt) || !nrow(tt)) next
    tt <- as.data.table(tt)
    tt <- merge(tt, egr, by = "stop_id")
    if (!nrow(tt)) next
    tt[, total := hms_to_s(start_time) + hms_to_s(duration) + walk - t0]
    tt[, access_walk := acc$walk[k]]
    tt[, access_stop := acc$stop_id[k]]
    cand <- tt[which.min(total)]
    if (is.null(best) || cand$total < best$total) best <- cand
  }
  if (is.null(best)) return(list(status = "unreachable"))

  list(
    status          = "ok",
    total_min       = best$total / 60,
    access_walk_min = best$access_walk / 60,
    wait_min        = (hms_to_s(best$start_time) - t0 - best$access_walk) / 60,
    ride_min        = hms_to_s(best$duration) / 60,
    egress_walk_min = best$walk / 60,
    n_transfers     = best$ntransfers,
    access_stop     = best$access_stop,
    egress_stop     = best$stop_id
  )
}

# ---- 4. run over every trip -------------------------------------------------
trips <- fread(TRIPS_CSV)
if (!is.null(ROW_LIMIT)) trips <- trips[seq_len(min(ROW_LIMIT, nrow(trips)))]
message("routing ", nrow(trips), " trips on ", N_CORES, " cores | scenario: ",
        SCENARIO, " | date: ", SERVICE_DATE)

started <- Sys.time()
res <- mclapply(seq_len(nrow(trips)), function(i) {
  r <- trips[i]
  out <- estimate_one(r$depart_lon, r$depart_lat, r$dest_lon, r$dest_lat,
                      r$depart_min_of_day * 60)
  data.table(
    record_id       = r$record_id,
    scenario        = SCENARIO,
    service_date    = SERVICE_DATE,
    gtfs_status     = out$status,
    gtfs_total_min  = if (is.null(out$total_min))       NA_real_ else out$total_min,
    gtfs_access_min = if (is.null(out$access_walk_min)) NA_real_ else out$access_walk_min,
    gtfs_wait_min   = if (is.null(out$wait_min))        NA_real_ else out$wait_min,
    gtfs_ride_min   = if (is.null(out$ride_min))        NA_real_ else out$ride_min,
    gtfs_egress_min = if (is.null(out$egress_walk_min)) NA_real_ else out$egress_walk_min,
    gtfs_transfers  = if (is.null(out$n_transfers))     NA_integer_ else out$n_transfers,
    access_stop_id  = if (is.null(out$access_stop))     NA_character_ else as.character(out$access_stop),
    egress_stop_id  = if (is.null(out$egress_stop))     NA_character_ else as.character(out$egress_stop)
  )
}, mc.cores = N_CORES)

res <- rbindlist(res)
message("done in ", round(difftime(Sys.time(), started, units = "mins"), 1), " min")

out <- merge(trips, res, by = "record_id", sort = FALSE)
fwrite(out, OUT_CSV)

cat("\n", SCENARIO, " @ ", SERVICE_DATE, "\n", sep = "")
print(table(out$gtfs_status, useNA = "ifany"))
ok <- out[gtfs_status == "ok"]
cat("median estimated door-to-door:", round(median(ok$gtfs_total_min), 1), "min\n")
cat("median survey travel time    :",
    round(median(ok$survey_travtime[ok$survey_travtime > 0], na.rm = TRUE), 1), "min\n")
cat("median model travel time     :", round(median(ok$model_travtime, na.rm = TRUE), 1), "min\n")
