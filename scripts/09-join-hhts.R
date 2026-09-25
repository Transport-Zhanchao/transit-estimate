# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

# Attach DVRPC Household Travel Survey attributes to the trip-level results, so
# the cut-vs-restore travel-time change can be modeled on who is travelling.
#
# Input : report/trip-level-results.csv   one row per routed trip (from 08)
#         data/4_trip_public.csv          trip attributes      key RECORD_ID
#         data/2_person_public.csv        person attributes    key HH_ID + PERSON_NUM
#         data/1_household_public.csv     household attributes key HH_ID
# Output: data/trip_hhts_joined.csv       same rows as the trip-level csv, plus
#                                         raw survey codes and model-ready features
#
# PERSON_ID and TRIP_ID are not used as keys: TRIP_ID is stored in scientific
# notation and has lost precision (see 01-pre-process.R). The trip -> person join
# uses HH_ID + PERSON_NUM, which are small integers and survive the csv round trip.
#
# Survey non-answers (98 / 99 "don't know" / "refused", 997+ on counts) are set to
# NA in the derived features; the raw columns keep the original codes.

suppressPackageStartupMessages(library(data.table))

res <- fread("report/trip-level-results.csv")

trip <- fread("data/4_trip_public.csv", select = c(
  "RECORD_ID", "HH_ID", "PERSON_NUM", "TOUR_TYPE", "TOUR_NUM", "TRIP_NUM",
  "O_LOC_TYPE", "D_LOC_TYPE", "ACTIV1", "PARTY", "MODE", "MODE_AGG",
  "TripFactor", "CompositeWeight"))
person <- fread("data/2_person_public.csv", encoding = "Latin-1", select = c(
  "HH_ID", "PERSON_NUM", "P_WEIGHT", "P_TOT_TRIPS", "GEND", "AGECAT", "RACE",
  "EDUCA", "LIC", "EMPLY", "WK_STAT", "JOBS", "HOURS", "OCCUP", "WK_MODE",
  "TCOMM", "PARK_SUB", "TRAN_SUB", "STUDE", "T_TRIP", "TAP"))
hh <- fread("data/1_household_public.csv", encoding = "Latin-1", select = c(
  "HH_ID", "HH_WEIGHT", "H_COUNTY", "H_TAZ", "A_TYPE", "HH_SIZE", "HH_WORK",
  "TOT_VEH", "OP_VEH", "TOT_BIKE", "CAR_SHARE", "RES_TYPE", "INCOME"))

stopifnot(!anyDuplicated(trip$RECORD_ID),
          !anyDuplicated(person, by = c("HH_ID", "PERSON_NUM")),
          !anyDuplicated(hh$HH_ID))

setnames(trip, "RECORD_ID", "record_id")
out <- merge(res, trip,   by = "record_id",               all.x = TRUE, sort = FALSE)
out <- merge(out, person, by = c("HH_ID", "PERSON_NUM"),  all.x = TRUE, sort = FALSE)
out <- merge(out, hh,     by = "HH_ID",                   all.x = TRUE, sort = FALSE)
stopifnot(nrow(out) == nrow(res))

# ---- derived features ---------------------------------------------------------
na_codes <- function(x, bad = c(97, 98, 99, 988)) fifelse(x %in% bad, NA_real_, as.numeric(x))

# Income bracket midpoints in $1,000s (codes 1-10); 250+ is set at 300.
inc_mid <- c(5, 17.5, 30, 42.5, 62.5, 87.5, 125, 175, 225, 300)

out[, `:=`(
  female        = fifelse(GEND %in% 1:2, as.integer(GEND == 2), NA_integer_),
  age_cat       = na_codes(AGECAT),
  age_65plus    = fifelse(AGECAT %in% 1:12, as.integer(AGECAT >= 10), NA_integer_),
  race_cat      = fcase(RACE == 1, "white", RACE == 2, "black", RACE == 3, "hispanic",
                        RACE == 5, "asian", RACE %in% c(4, 6, 97, 100), "other",
                        default = NA_character_),
  college_deg   = fifelse(EDUCA %in% 1:6, as.integer(EDUCA >= 5), NA_integer_),
  has_license   = fifelse(LIC %in% 1:2, as.integer(LIC == 1), NA_integer_),
  employed      = fifelse(EMPLY %in% 1:2, as.integer(EMPLY == 1), NA_integer_),
  student       = fifelse(STUDE %in% 1:3, as.integer(STUDE %in% 1:2), NA_integer_),
  transit_trips_wk = fifelse(T_TRIP >= 0 & T_TRIP <= 50, as.numeric(T_TRIP),
                     fifelse(T_TRIP == 997, 50, NA_real_)),
  transit_subsidy  = fifelse(TRAN_SUB %in% 1:2, as.integer(TRAN_SUB == 1), NA_integer_),
  income_k      = fifelse(INCOME %in% 1:10, inc_mid[pmin(pmax(INCOME, 1L), 10L)], NA_real_),
  low_income    = fifelse(INCOME %in% 1:10, as.integer(INCOME <= 3), NA_integer_),
  hh_size       = na_codes(HH_SIZE),
  hh_workers    = na_codes(HH_WORK),
  hh_vehicles   = na_codes(TOT_VEH),
  area_type     = fcase(A_TYPE %in% 1:2, "cbd", A_TYPE == 3, "urban",
                        A_TYPE == 4, "suburban", A_TYPE %in% 5:6, "rural",
                        default = NA_character_),
  work_tour     = fifelse(TOUR_TYPE %in% 1:3, as.integer(TOUR_TYPE == 1), NA_integer_),
  home_based    = fifelse(TOUR_TYPE %in% 1:3, as.integer(TOUR_TYPE %in% 1:2), NA_integer_)
)]
out[, `:=`(
  zero_veh_hh  = as.integer(hh_vehicles == 0),
  veh_per_adult = fifelse(hh_size > 0, hh_vehicles / hh_size, NA_real_)
)]

setcolorder(out, c("record_id", "sample", "HH_ID", "PERSON_NUM"))
setorder(out, sample, record_id)
fwrite(out, "data/trip_hhts_joined.csv", na = "NA")

# ---- join report ----------------------------------------------------------------
cat("rows:", nrow(out), " cols:", ncol(out), "\n")
cat("matched trip file    :", sum(!is.na(out$HH_ID)), "\n")
cat("matched person file  :", sum(!is.na(out$P_WEIGHT)), "\n")
cat("matched household    :", sum(!is.na(out$HH_WEIGHT)), "\n")
cat("distinct persons     :", uniqueN(out, by = c("HH_ID", "PERSON_NUM")), "\n")
cat("distinct households  :", uniqueN(out$HH_ID), "\n")
feat <- c("female", "age_cat", "race_cat", "college_deg", "has_license", "employed",
          "income_k", "hh_vehicles", "area_type", "work_tour", "transit_trips_wk")
cat("\nNA share in features:\n")
print(round(sapply(out[, ..feat], function(x) mean(is.na(x))), 3))
