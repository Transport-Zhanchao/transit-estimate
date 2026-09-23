# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

# Pull out the trips that involve Regional Rail and write them to their own file.
#
# "Involves Regional Rail" covers two kinds of record:
#   rail_leg   - the trip itself is MODE 22
#   feeder_leg - a bus/subway/trolley trip that belongs to the same journey as a
#                rail leg, i.e. the ride to or from the station
# The survey splits a multimodal journey into one record per mode and marks the
# intermediate stop with activity code 19, "change type of transportation", so
# journeys are rebuilt by chaining consecutive trips of a person across that code.
#
# Everything else (departure-time filter, weekday, non-holiday, TAZ centroids,
# peak flag) matches 01-pre-process.R, so the output can be fed straight into
# 04-estimate-traveltime.R by pointing TRIPS_CSV at it.
#
# Output: data/transit_regional_rail.csv

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
})

raw <- read.csv("data/4_trip_public.csv")

# ---- journeys: chain consecutive trips linked by a transfer activity ---------
raw <- raw %>%
  arrange(PERSON_ID, TRIP_NUM) %>%
  mutate(continues = !is.na(ACTIV1) & ACTIV1 == 19)
raw <- raw %>%
  mutate(new_journey = c(TRUE, !(head(continues, -1) &
                                   tail(PERSON_ID, -1) == head(PERSON_ID, -1))),
         journey_id  = cumsum(new_journey))

rail_journeys <- raw %>% filter(MODE == 22) %>% pull(journey_id) %>% unique()

# ---- same filters as 01-pre-process.R, but keeping Regional Rail ---------------
hh <- read.csv("data/1_household_public.csv", encoding = "latin1") %>%
  select(HH_ID, TRAV_DOW, TRAV_DATE, HOLIDAY, HOL_TYPE)

trips <- raw %>%
  filter(O_STATE == 42, D_STATE == 42, MODE_AGG == 5,
         MODE %in% c(14, 21, 22, 23)) %>%
  mutate(DEPART = str_trim(as.character(DEPART))) %>%
  filter(str_detect(DEPART, "^\\d{1,2}:[0-5][0-9]$")) %>%
  mutate(DEPART_HOUR = as.integer(str_extract(DEPART, "^\\d{1,2}")),
         DEPART_MIN  = as.integer(str_extract(DEPART, "\\d{2}$"))) %>%
  filter(DEPART_HOUR < 24) %>%
  mutate(DEPART_MIN_OF_DAY = DEPART_HOUR * 60 + DEPART_MIN) %>%
  left_join(hh, by = "HH_ID") %>%
  filter(TRAV_DOW %in% 1:5, HOL_TYPE %in% c(0, 3))

# keep only the records that involve rail, and say how
trips <- trips %>%
  filter(MODE == 22 | journey_id %in% rail_journeys) %>%
  mutate(rr_role = if_else(MODE == 22, "rail_leg", "feeder_leg"))

# ---- TAZ centroids ----------------------------------------------------------
taz_centroid <- st_read("data/taz.geojson", quiet = TRUE) %>%
  st_transform(26918) %>%
  st_centroid() %>%
  st_transform(4326)
taz_centroid <- taz_centroid %>%
  mutate(lon = st_coordinates(.)[, 1], lat = st_coordinates(.)[, 2]) %>%
  st_drop_geometry() %>%
  select(taz, lon, lat)

trips <- trips %>%
  left_join(taz_centroid %>% rename(O_TAZ = taz, depart_lon = lon, depart_lat = lat),
            by = "O_TAZ") %>%
  left_join(taz_centroid %>% rename(D_TAZ = taz, dest_lon = lon, dest_lat = lat),
            by = "D_TAZ") %>%
  filter(!is.na(depart_lon), !is.na(dest_lon))

# ---- peak flag, same windows as 01-pre-process.R -------------------------------
AM_PEAK <- c(6 * 60, 9 * 60 + 30)
PM_PEAK <- c(16 * 60, 19 * 60)
trips <- trips %>%
  mutate(peak_period = case_when(
           DEPART_MIN_OF_DAY >= AM_PEAK[1] & DEPART_MIN_OF_DAY < AM_PEAK[2] ~ "am_peak",
           DEPART_MIN_OF_DAY >= PM_PEAK[1] & DEPART_MIN_OF_DAY < PM_PEAK[2] ~ "pm_peak",
           TRUE ~ "off_peak"),
         is_peak = peak_period != "off_peak")

out <- trips %>%
  transmute(record_id         = RECORD_ID,
            person_id         = PERSON_ID,
            journey_id,
            trip_num          = TRIP_NUM,
            mode              = MODE,
            rr_role,
            depart_time       = DEPART,
            depart_min_of_day = DEPART_MIN_OF_DAY,
            depart_lon, depart_lat,
            dest_lon, dest_lat,
            o_county          = O_COUNTY,
            d_county          = D_COUNTY,
            peak_period, is_peak,
            survey_travtime   = Survey_TravTime,
            model_travtime    = Model_TravTime)

write.csv(out, "data/transit_regional_rail.csv", row.names = FALSE)

cat("records involving Regional Rail:", nrow(out), "\n")
print(table(out$rr_role))
print(table(out$peak_period))
cat("journeys represented:", length(unique(out$journey_id)), "\n")
cat("multi-leg journeys  :", sum(table(out$journey_id) > 1), "\n")
