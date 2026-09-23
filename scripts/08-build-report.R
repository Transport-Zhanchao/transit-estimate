# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

# Builds the two deliverables in report/:
#
#   report/trip-level-results.csv   one row per routed trip, both scenarios
#   report/report.md                the report, filled in from report/report-template.md
#
# Trips that could not be routed under a scenario carry NA in that scenario's
# columns; they are kept in the file rather than dropped, so the csv is the whole
# sample and the routed subset is a filter on `routed`.

suppressPackageStartupMessages(library(data.table))
dir.create("report", showWarnings = FALSE)

PHILA <- 42101
county_name <- c("42101" = "Philadelphia", "42091" = "Montgomery",
                 "42045" = "Delaware", "42017" = "Bucks", "42029" = "Chester")
mode_label <- c("14" = "Bus / trolleybus", "21" = "Subway / El",
                "23" = "Trolley / light rail", "22" = "Regional Rail")

# ---- 1. trip-level table -----------------------------------------------------
bus  <- fread("data/transit_simple_estimates.csv")
rail <- fread("data/transit_regional_rail_estimates.csv")

# MODE and county were dropped from the slim bus table; take them back.
wk <- fread("data/transit_weekday_timed.csv")[
  , .(record_id = RECORD_ID, mode = MODE, o_county = O_COUNTY, d_county = D_COUNTY)]
bus <- merge(bus, wk, by = "record_id", all.x = TRUE, sort = FALSE)
bus[, `:=`(rr_role = NA_character_, person_id = NA_integer_,
           journey_id = NA_integer_, trip_num = NA_integer_)]

bus [, `:=`(sample = "bus_subway_trolley", feed = "City Transit",
            service_date = "2025-10-15")]
rail[, `:=`(sample = "regional_rail", feed = "City Transit + Regional Rail",
            service_date = "2025-11-05")]

cols <- c("record_id", "sample", "feed", "service_date", "person_id", "journey_id",
          "trip_num", "mode", "rr_role", "depart_time", "depart_min_of_day",
          "peak_period", "is_peak", "o_county", "d_county",
          "depart_lon", "depart_lat", "dest_lon", "dest_lat",
          "survey_travtime", "model_travtime",
          "tt_cut_mean_min", "tt_cut_sd_min", "tt_cut_n_ok",
          "tt_restore_mean_min", "tt_restore_sd_min", "tt_restore_n_ok")
trips <- rbindlist(list(bus[, ..cols], rail[, ..cols]), use.names = TRUE)

# The 22 bus and subway legs that feed a station appear in both samples: once on
# the City Transit feed, once on the merged feed. Flag them rather than drop one
# copy, so either sample can be reconstructed exactly.
dup <- trips[, .N, by = record_id][N > 1, record_id]
trips[, in_both_samples := record_id %in% dup]

setnames(trips,
  c("tt_cut_mean_min", "tt_restore_mean_min", "mode"),
  c("cut_average_min", "restore_average_min", "mode_code"))

trips[, `:=`(
  mode          = mode_label[as.character(mode_code)],
  o_county_name = county_name[as.character(o_county)],
  d_county_name = county_name[as.character(d_county)],
  geography = fifelse(o_county == PHILA & d_county == PHILA, "Within Philadelphia",
              fifelse(o_county != d_county, "Cross-county",
                      "Within one suburban county")),
  routed = fcase(
    !is.na(cut_average_min) & !is.na(restore_average_min), "both",
     is.na(cut_average_min) & !is.na(restore_average_min), "restore_only",
    !is.na(cut_average_min) &  is.na(restore_average_min), "cut_only",
    default = "neither"),
  delta_min = round(cut_average_min - restore_average_min, 3),
  delta_pct = round(100 * (cut_average_min - restore_average_min) /
                      restore_average_min, 2)
)]
for (v in c("cut_average_min", "restore_average_min", "tt_cut_sd_min",
            "tt_restore_sd_min", "survey_travtime", "model_travtime"))
  trips[, (v) := round(as.numeric(get(v)), 3)]

# Origin and destination TAZ. Neither estimate file carries them - the slim bus
# table kept only the centroids, and the rail sample was cut before the TAZ join -
# so take them from the source trip file, where RECORD_ID is unique.
taz <- fread("data/4_trip_public.csv",
             select = c("RECORD_ID", "O_TAZ", "D_TAZ"))
setnames(taz, c("record_id", "o_taz", "d_taz"))
trips <- merge(trips, taz, by = "record_id", all.x = TRUE, sort = FALSE)

# `trips` keeps every column for the aggregates below; the delivered csv is the
# plain per-trip result only.
setorder(trips, sample, record_id)

out <- trips[, .(record_id, sample, mode, o_taz, d_taz,
                 restore_average_min, cut_average_min, delta_min)]
stopifnot(!anyNA(out$o_taz), !anyNA(out$d_taz))
fwrite(out, "report/trip-level-results.csv", na = "NA")
cat("report/trip-level-results.csv:", nrow(out), "rows,", ncol(out), "cols\n")
print(trips[, .N, by = .(sample, routed)][order(sample, -N)])

# ---- 2. scheduled service (capacity) from the feeds --------------------------
# GTFS carries no seat counts, so "capacity" here is scheduled service: trips
# operated on a weekday, and stop events (a train or bus calling at a stop),
# which is the trips measure weighted by how many stops each one serves.
read_txt <- function(zip, name) {
  f <- paste0(name, ".txt")
  if (!f %in% unzip(zip, list = TRUE)$Name) return(NULL)
  x <- fread(cmd = sprintf("unzip -p '%s' '%s'", zip, f),
             colClasses = "character", strip.white = TRUE)
  setnames(x, trimws(names(x))); x
}

# `svc_date`, not `date`: calendar_dates.txt has a column of that name and the
# argument would be masked by it inside the data.table subsets below.
service_ids <- function(zip, svc_date) {
  dow <- tolower(weekdays(as.Date(svc_date, "%Y%m%d")))
  cal <- read_txt(zip, "calendar"); cd <- read_txt(zip, "calendar_dates")
  act <- character()
  if (!is.null(cal) && dow %in% names(cal))
    act <- cal[get(dow) == "1" & start_date <= svc_date & end_date >= svc_date,
               service_id]
  if (!is.null(cd)) {
    act <- union(act,   cd[date == svc_date & exception_type == "1", service_id])
    act <- setdiff(act, cd[date == svc_date & exception_type == "2", service_id])
  }
  act
}

feed_service <- function(zip, svc_date) {
  tr <- read_txt(zip, "trips")[service_id %in% service_ids(zip, svc_date)]
  rt <- read_txt(zip, "routes")
  if (!"route_short_name" %in% names(rt)) rt[, route_short_name := ""]
  rt[, line := fifelse(!is.na(route_short_name) & route_short_name != "",
                       route_short_name, route_long_name)]
  tr <- merge(tr, rt[, .(route_id, line)], by = "route_id", all.x = TRUE)
  st <- read_txt(zip, "stop_times")[trip_id %in% tr$trip_id]
  st[, dep := fifelse(departure_time != "", departure_time, arrival_time)]
  st <- st[dep != ""]
  starts <- st[, .(start = min(dep), stops = .N), by = trip_id]
  starts[, hour := as.integer(substr(start, 1, regexpr(":", start) - 1)) %% 24]
  merge(tr[, .(trip_id, line)], starts, by = "trip_id")
}

bands <- function(h) fcase(h < 6, "Before 6", h < 9, "AM peak 6-9",
                           h < 15, "Midday 9-15", h < 19, "PM peak 15-19",
                           default = "Evening 19-24")
BAND_ORDER <- c("Before 6", "AM peak 6-9", "Midday 9-15", "PM peak 15-19",
                "Evening 19-24")

cap_table <- function(cut_zip, res_zip, date, by) {
  c1 <- feed_service(cut_zip, date); r1 <- feed_service(res_zip, date)
  c1[, band := bands(hour)]; r1[, band := bands(hour)]
  agg <- function(d) d[, .(trips = .N, stop_events = sum(stops)), by = c(by)]
  m <- merge(agg(c1), agg(r1), by = by, all = TRUE, suffixes = c("_cut", "_res"))
  for (v in names(m)[-1]) m[is.na(get(v)), (v) := 0L]
  m[, `:=`(diff = trips_cut - trips_res,
           pct  = round(100 * (trips_cut - trips_res) / trips_res))]
  tot <- data.table(x = "TOTAL", trips_cut = sum(m$trips_cut),
                    stop_events_cut = sum(m$stop_events_cut),
                    trips_res = sum(m$trips_res),
                    stop_events_res = sum(m$stop_events_res))
  tot[, `:=`(diff = trips_cut - trips_res,
             pct = round(100 * (trips_cut - trips_res) / trips_res))]
  setnames(tot, "x", by)
  rbind(m, tot)
}

md_cap <- function(tab, by, title, lv = NULL) {   # `lv`, not `order`: it would
  if (!is.null(lv))                                # shadow the order() below
    tab <- tab[order(match(get(by), c(lv, "TOTAL")))]
  out <- c(paste("###", title), "",
           sprintf("| %s | Cut | Restore | Change | %% |", by),
           "|---|---|---|---|---|")
  for (i in seq_len(nrow(tab))) {
    r <- tab[i]
    lab <- if (r[[by]] == "TOTAL") "**TOTAL**" else r[[by]]
    out <- c(out, sprintf("| %s | %s | %s | %s | %+d%% |", lab,
                          format(r$trips_cut, big.mark = ","),
                          format(r$trips_res, big.mark = ","),
                          sprintf("%+s", format(r$diff, big.mark = ",")), r$pct))
  }
  c(out, "")
}

rail_line <- cap_table("data/gtfs/cut_rail.zip", "data/gtfs/restore_rail.zip",
                       "20251105", "line")
rail_band <- cap_table("data/gtfs/cut_rail.zip", "data/gtfs/restore_rail.zip",
                       "20251105", "band")
bus_band  <- cap_table("data/gtfs/cut.zip", "data/gtfs/restore.zip",
                       "20251015", "band")


# ---- 3. result tables --------------------------------------------------------
res <- trips[routed == "both"]
res[, cell := fifelse(o_county != d_county & peak_period != "off_peak",
                      "Cross-county, peak", "Everything else")]
res[, period := c(am_peak = "AM peak", pm_peak = "PM peak",
                  off_peak = "Off-peak")[peak_period]]
BUS <- "bus_subway_trolley"; RAIL <- "regional_rail"

st <- function(d) list(
  n = nrow(d), cut = median(d$cut_average_min), res = median(d$restore_average_min),
  med = median(d$delta_min), mean = mean(d$delta_min), pct = median(d$delta_pct),
  gt10 = 100 * mean(d$delta_min > 10), faster = 100 * mean(d$delta_min < 0))

# label, n, cut, restore, median, mean, %, share >10 min
row7 <- function(lab, d, bold = FALSE) {
  s <- st(d)
  sprintf("| %s | %s | %.1f | %.1f | %+.2f | %+.2f | %+.1f%% | %.0f%% |",
          if (bold) paste0("**", lab, "**") else lab,
          format(s$n, big.mark = ","), s$cut, s$res, s$med, s$mean, s$pct, s$gt10)
}
HEAD7 <- c("| | n | Cut | Restore | Median Δ | Mean Δ | Median Δ% | Share > 10 min |",
           "|---|---|---|---|---|---|---|---|")

tbl <- function(rows) paste(c(HEAD7, rows), collapse = "\n")

bus_mode <- tbl(c(
  row7("All bus / subway / trolley", res[sample == BUS], TRUE),
  vapply(c("Bus / trolleybus", "Subway / El", "Trolley / light rail"),
         function(m) row7(m, res[sample == BUS & mode == m]), character(1))))
bus_period <- tbl(vapply(c("AM peak", "PM peak", "Off-peak"),
  function(p) row7(p, res[sample == BUS & period == p]), character(1)))
bus_geo <- tbl(vapply(
  c("Within Philadelphia", "Cross-county", "Within one suburban county"),
  function(g) row7(g, res[sample == BUS & geography == g]), character(1)))

rail_role <- tbl(c(
  row7("All Regional Rail trips", res[sample == RAIL], TRUE),
  row7("Train legs", res[sample == RAIL & rr_role == "rail_leg"]),
  row7("Feeder bus / subway legs", res[sample == RAIL & rr_role == "feeder_leg"])))
rail_period <- tbl(vapply(c("AM peak", "PM peak", "Off-peak"),
  function(p) row7(p, res[sample == RAIL & period == p]), character(1)))
rail_geo <- tbl(vapply(
  c("Cross-county", "Within Philadelphia", "Within one suburban county"),
  function(g) row7(g, res[sample == RAIL & geography == g]), character(1)))

# rail vs bus on the same geography x period cells
cross <- c("| Geography | Period | Rail median Δ | Rail n | Non-rail median Δ | Non-rail n |",
           "|---|---|---|---|---|---|")
for (g in c("Cross-county", "Within Philadelphia"))
  for (p in c("AM peak", "PM peak", "Off-peak")) {
    a <- res[sample == RAIL & geography == g & period == p]
    b <- res[sample == BUS  & geography == g & period == p]
    cross <- c(cross, sprintf("| %s | %s | %+.2f | %d | %+.2f | %d |",
                              g, p, median(a$delta_min), nrow(a),
                              median(b$delta_min), nrow(b)))
  }
cross <- paste(cross, collapse = "\n")

cell <- c("| | Regional Rail | Non-rail |", "|---|---|---|")
for (cl in c("Cross-county, peak", "Everything else")) {
  a <- res[sample == RAIL & cell == cl]; b <- res[sample == BUS & cell == cl]
  v <- sprintf("%+.2f", median(a$delta_min))
  if (cl == "Cross-county, peak") v <- paste0("**", v, "**")   # the row that matters
  cell <- c(cell, sprintf("| %s | %s (n=%d) | %+.2f (n=%s) |", cl, v, nrow(a),
                          median(b$delta_min), format(nrow(b), big.mark = ",")))
}
a <- res[sample == RAIL]; b <- res[sample == BUS]
cell <- c(cell, sprintf("| All trips | %+.2f (n=%d) | %+.2f (n=%s) |",
                        median(a$delta_min), nrow(a), median(b$delta_min),
                        format(nrow(b), big.mark = ",")))
cell <- paste(cell, collapse = "\n")

cap_md <- function(tab, by, lv = NULL) {
  if (!is.null(lv)) tab <- tab[order(match(get(by), c(lv, "TOTAL")))]
  out <- c(sprintf("| %s | Cut | Restore | Change | %% |",
                   if (by == "line") "Line" else "Period"), "|---|---|---|---|---|")
  for (i in seq_len(nrow(tab))) {
    r <- tab[i]; lab <- if (r[[by]] == "TOTAL") "**TOTAL**" else r[[by]]
    out <- c(out, sprintf("| %s | %s | %s | %s | %+d%% |", lab,
                          format(r$trips_cut, big.mark = ","),
                          format(r$trips_res, big.mark = ","),
                          sprintf("%+s", format(r$diff, big.mark = ",")), r$pct))
  }
  paste(out, collapse = "\n")
}
rl <- rail_line[line == "TOTAL"]; bl <- bus_band[band == "TOTAL"]
se <- function(r) sprintf("%s vs %s, %+.0f%%",
  format(r$stop_events_cut, big.mark = ","), format(r$stop_events_res, big.mark = ","),
  100 * (r$stop_events_cut - r$stop_events_res) / r$stop_events_res)

# ---- 4. write the report -----------------------------------------------------
# Read and write the template as raw bytes: Rscript may not be in a UTF-8
# locale, and readLines/writeLines would turn the report's non-ASCII characters
# (delta, em dash, en dash) into literal <U+....> escapes.
rep <- rawToChar(readBin("report/report-template.md", "raw",
                         file.info("report/report-template.md")$size))
Encoding(rep) <- "UTF-8"
subs <- list(
  BUS_MODE = bus_mode, BUS_PERIOD = bus_period, BUS_GEO = bus_geo,
  RAIL_ROLE = rail_role, RAIL_PERIOD = rail_period, RAIL_GEO = rail_geo,
  CROSS = cross, CELL = cell,
  CAP_RAIL_LINE = cap_md(rail_line, "line"),
  CAP_RAIL_BAND = cap_md(rail_band, "band", BAND_ORDER),
  CAP_BUS_BAND  = cap_md(bus_band,  "band", BAND_ORDER),
  SE_RAIL = se(rl), SE_BUS = se(bl))
for (k in names(subs))
  rep <- gsub(paste0("{{", k, "}}"), subs[[k]], rep, fixed = TRUE, useBytes = TRUE)

con <- file("report/report.md", open = "wb")
writeBin(charToRaw(rep), con); close(con)
cat("report/report.md written\n")
left <- regmatches(rep, gregexpr("\\{\\{[A-Z_]+\\}\\}", rep))[[1]]
if (length(left)) cat("UNFILLED PLACEHOLDERS:", paste(unique(left), collapse = " "), "\n")
