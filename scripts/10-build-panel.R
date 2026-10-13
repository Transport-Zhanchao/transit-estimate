# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

# Build a trip x scenario panel of estimated travel times with the survey
# demographics and trip geography attached, for the regression models in 11.
#
# Input : data/trip_hhts_joined.csv         one row per trip, cut / restore times
#                                           and survey features (from 09)
#         data/transit_simple.csv           origin / destination lon-lat (bus etc.)
#         data/transit_regional_rail.csv    origin / destination lon-lat (rail)
#         data/taz.geojson                  TAZ polygons, for origin county / area type
# Output: data/trip_panel.csv               two rows per trip: scenario = restore / cut
#
# Geography is taken from the trip lon-lat rather than o_taz / d_taz: about a
# quarter of the survey TAZ ids do not appear in taz.geojson, while every trip
# has coordinates. Distances are great-circle km; Center City is City Hall.
#
# Trips that could not be routed under both scenarios (delta_min NA) are dropped,
# so the panel is balanced.

suppressPackageStartupMessages({
  library(data.table)
  library(sf)
})

d <- fread("data/trip_hhts_joined.csv")

xy_cols <- c("record_id", "depart_lon", "depart_lat", "dest_lon", "dest_lat",
             "depart_min_of_day", "is_peak")
# A few trips sit in both source files (rail feeder legs), so join on sample too.
xy <- rbind(
  fread("data/transit_simple.csv",        select = xy_cols)[, sample := "bus_subway_trolley"],
  fread("data/transit_regional_rail.csv", select = xy_cols)[, sample := "regional_rail"])
stopifnot(!anyDuplicated(xy, by = c("sample", "record_id")))
d <- merge(d, xy, by = c("sample", "record_id"), all.x = TRUE, sort = FALSE)
stopifnot(!anyNA(d$depart_lon))

# ---- geography ----------------------------------------------------------------
city_hall <- c(-75.1636, 39.9526)
hav_km <- function(lon1, lat1, lon2, lat2) {
  r <- pi / 180
  a <- sin((lat2 - lat1) * r / 2)^2 +
       cos(lat1 * r) * cos(lat2 * r) * sin((lon2 - lon1) * r / 2)^2
  2 * 6371 * asin(sqrt(a))
}
d[, `:=`(
  o_dist_cc_km = hav_km(depart_lon, depart_lat, city_hall[1], city_hall[2]),
  d_dist_cc_km = hav_km(dest_lon,   dest_lat,   city_hall[1], city_hall[2]),
  trip_km      = hav_km(depart_lon, depart_lat, dest_lon, dest_lat)
)]

sf_use_s2(FALSE)
taz <- st_read("data/taz.geojson", quiet = TRUE)[, c("co_name", "area_type")]
o_pts <- st_as_sf(unique(d[, .(record_id, depart_lon, depart_lat)], by = "record_id"),
                  coords = c("depart_lon", "depart_lat"), crs = 4326)
o_taz <- suppressMessages(st_join(o_pts, taz, join = st_within, left = TRUE))
o_taz <- unique(as.data.table(st_drop_geometry(o_taz)), by = "record_id")
setnames(o_taz, c("co_name", "area_type"), c("o_county", "o_area_code"))
d <- merge(d, o_taz, by = "record_id", all.x = TRUE, sort = FALSE)
d[, `:=`(
  o_philly  = as.integer(o_county == "Philadelphia"),
  o_area    = fcase(o_area_code %in% 1:2, "cbd", o_area_code == 3, "urban",
                    o_area_code == 4, "suburban", o_area_code %in% 5:6, "rural",
                    default = NA_character_)
)]

# ---- model-ready extras ---------------------------------------------------------
d[, `:=`(
  person_id = HH_ID * 100L + PERSON_NUM,
  rail      = as.integer(sample == "regional_rail"),
  black     = fifelse(is.na(race_cat), NA_integer_, as.integer(race_cat == "black")),
  nonwhite_other = fifelse(is.na(race_cat), NA_integer_,
                           as.integer(race_cat %in% c("hispanic", "asian", "other"))),
  peak      = as.integer(is_peak)
)]

# ---- reshape to trip x scenario ---------------------------------------------------
d <- d[!is.na(delta_min)]
keep <- c("record_id", "person_id", "HH_ID", "sample", "mode", "rail", "delta_min",
          "o_dist_cc_km", "d_dist_cc_km", "trip_km", "o_county", "o_philly", "o_area",
          "depart_min_of_day", "peak",
          "female", "age_cat", "age_65plus", "race_cat", "black", "nonwhite_other",
          "college_deg", "has_license", "employed", "student", "transit_trips_wk",
          "transit_subsidy", "income_k", "low_income", "hh_size", "hh_workers",
          "hh_vehicles", "zero_veh_hh", "veh_per_adult", "area_type", "work_tour",
          "home_based", "P_WEIGHT", "CompositeWeight")
panel <- melt(d[, c(keep, "restore_average_min", "cut_average_min"), with = FALSE],
              measure.vars = c("restore_average_min", "cut_average_min"),
              variable.name = "scenario", value.name = "tt_min")
panel[, scenario := fifelse(scenario == "cut_average_min", "cut", "restore")]
panel[, cut := as.integer(scenario == "cut")]
setcolorder(panel, c("record_id", "scenario", "cut", "tt_min"))
setorder(panel, sample, record_id, cut)
stopifnot(panel[, .N, .(sample, record_id)][, all(N == 2)])
fwrite(panel, "data/trip_panel.csv", na = "NA")

# ---- report -----------------------------------------------------------------------
cat("trips:", uniqueN(panel, by = c("sample", "record_id")), " panel rows:", nrow(panel),
    " persons:", uniqueN(panel$person_id), "\n")
cat("origin outside TAZ layer:", sum(is.na(d$o_county)), "\n")
print(panel[, .(mean_tt = round(mean(tt_min), 2), median_tt = round(median(tt_min), 2)),
            by = .(sample, scenario)])
cat("\norigin distance to City Hall (km):\n"); print(summary(d$o_dist_cc_km))
