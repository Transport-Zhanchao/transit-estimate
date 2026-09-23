# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

library(tidyverse)
library(sf)

dat<-read.csv("data/4_trip_public.csv")

transit<-dat%>%
  filter(O_STATE == 42)
transit<-transit%>%
  filter(D_STATE == 42)

transit<-transit%>%
  filter(MODE_AGG == 5)

transit_mode<-transit%>%
  group_by(MODE)%>%
  summarise(n=n())

# 14 SEPTA bus/trolleybus, 21 subway/El, 23 trolley/light rail.
# Regional Rail (22) is left out: the GTFS feeds we route with are City Transit
# only, so those trips cannot be estimated as rail.
transit <- transit %>%
  filter(MODE %in% c(14, 21, 23))

write.csv(transit, "data/transit.csv")

# ---- Step 1: drop records whose DEPART is not an actual clock time ----------
# DEPART holds "H:MM" strings, but also survey codes (9998 = don't know,
# 9999 = refused), blanks, and a couple of Excel day-fractions (e.g. 0.708333).
# Keep only values matching H:MM / HH:MM with a real hour and minute.
transit <- transit %>%
  mutate(DEPART = str_trim(as.character(DEPART))) %>%
  filter(str_detect(DEPART, "^\\d{1,2}:[0-5][0-9]$")) %>%
  mutate(
    DEPART_HOUR = as.integer(str_extract(DEPART, "^\\d{1,2}")),
    DEPART_MIN  = as.integer(str_extract(DEPART, "\\d{2}$"))
  ) %>%
  filter(DEPART_HOUR < 24) %>%
  mutate(DEPART_MIN_OF_DAY = DEPART_HOUR * 60 + DEPART_MIN)

# ---- Step 2: drop weekend trips --------------------------------------------
# Day of week lives in the household file (TRAV_DOW), not in the trip file.
# TRAV_DOW: 1 Monday ... 5 Friday (the survey only assigns weekday travel dates,
# so this filter is a safety net rather than a real cut).
hh_path <- "data/1_household_public.csv"
if (file.exists(hh_path)) {
  hh <- read.csv(hh_path, encoding = "latin1")
  transit <- transit %>%
    left_join(hh %>% select(HH_ID, TRAV_DOW, TRAV_DATE, HOLIDAY, HOL_TYPE),
              by = "HH_ID") %>%
    filter(TRAV_DOW %in% 1:5)

  # ---- Step 3: drop holiday travel days ------------------------------------
  # HOL_TYPE: 0 no holiday, 1 major, 2 minor, 3 very minor.
  # The dictionary notes very minor holidays have an insignificant effect on
  # travel, so keep 0 and 3 and drop major/minor holidays.
  transit <- transit %>%
    filter(HOL_TYPE %in% c(0, 3))
} else {
  message("NOTE: ", hh_path, " not found - weekend and holiday filters skipped. ",
          "All travel dates in this survey are Mon-Fri by design; ",
          "holiday flags (HOLIDAY / HOL_TYPE) live in the household file.")
}

# ---- Step 4: attach TAZ centroids for origin and destination ---------------
# TAZ polygons: DVRPC demographics/taz FeatureServer (3,363 zones), pulled as
# GeoJSON (EPSG:4326) into data/taz.geojson. Centroids are computed in the
# service's native projected CRS (EPSG:26918, UTM 18N) and returned as lon/lat.
taz <- st_read("data/taz.geojson", quiet = TRUE)

taz_centroid <- taz %>%
  st_transform(26918) %>%
  st_centroid() %>%
  st_transform(4326)

taz_centroid <- taz_centroid %>%
  mutate(
    lon = st_coordinates(.)[, 1],
    lat = st_coordinates(.)[, 2]
  ) %>%
  st_drop_geometry() %>%
  select(taz, lon, lat)

transit <- transit %>%
  left_join(taz_centroid %>%
              rename(O_TAZ = taz, depart_lon = lon, depart_lat = lat),
            by = "O_TAZ") %>%
  left_join(taz_centroid %>%
              rename(D_TAZ = taz, dest_lon = lon, dest_lat = lat),
            by = "D_TAZ") %>%
  mutate(
    depart_point = if_else(is.na(depart_lon), NA_character_,
                           sprintf("POINT (%.6f %.6f)", depart_lon, depart_lat)),
    dest_point   = if_else(is.na(dest_lon), NA_character_,
                           sprintf("POINT (%.6f %.6f)", dest_lon, dest_lat))
  )

message("dropping trips without an origin centroid: ",
        sum(is.na(transit$depart_lon)),
        "; without a destination centroid: ", sum(is.na(transit$dest_lon)))

# Every non-missing O_TAZ / D_TAZ matches a zone, so the only gaps are trips
# whose TAZ itself is NA - drop them, they cannot be placed in space.
transit <- transit %>%
  filter(!is.na(depart_lon), !is.na(dest_lon))

write.csv(transit, "data/transit_weekday_timed.csv", row.names = FALSE)

# ---- Step 5: SEPTA peak / off-peak flag ------------------------------------
# SEPTA's peak definition is the Regional Rail fare rule: on weekdays, peak is
# travel arriving in Center City (30th St / Suburban / Jefferson) between
# 6:00 and 9:30 a.m., or leaving Center City between 4:00 and 7:00 p.m.;
# everything else is off-peak. The survey records a trip's own departure time,
# not a Center City arrival, so the windows are applied to DEPART.
AM_PEAK <- c(6 * 60, 9 * 60 + 30)   # 6:00 - 9:30
PM_PEAK <- c(16 * 60, 19 * 60)      # 4:00 - 7:00

transit <- transit %>%
  mutate(
    peak_period = case_when(
      DEPART_MIN_OF_DAY >= AM_PEAK[1] & DEPART_MIN_OF_DAY < AM_PEAK[2] ~ "am_peak",
      DEPART_MIN_OF_DAY >= PM_PEAK[1] & DEPART_MIN_OF_DAY < PM_PEAK[2] ~ "pm_peak",
      TRUE ~ "off_peak"
    ),
    is_peak = peak_period != "off_peak"
  )

print(table(transit$peak_period))

# ---- Step 6: slim export ----------------------------------------------------
# One row per trip: id, origin/destination TAZ centroids, travel time, and
# departure time.
# RECORD_ID is the trip key here - TRIP_ID is stored in scientific notation in
# the source csv and has already lost precision (845 distinct values for 2,015
# trips), so it cannot identify a trip.
transit_simple <- transit %>%
  transmute(
    record_id        = RECORD_ID,
    depart_time      = DEPART,
    depart_min_of_day = DEPART_MIN_OF_DAY,
    depart_lon, depart_lat,
    dest_lon, dest_lat,
    peak_period,
    is_peak,
    survey_travtime  = Survey_TravTime,
    model_travtime   = Model_TravTime
  )

write.csv(transit_simple, "data/transit_simple.csv", row.names = FALSE)
