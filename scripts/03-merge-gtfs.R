# Merge each City Transit feed with its Regional Rail feed into one feed, so a
# trip can walk from a bus to a train station and ride both.
#
#   cut.zip     + cut_rail.zip     -> data/gtfs/cut_merged.zip
#   restore.zip + restore_rail.zip -> data/gtfs/restore_merged.zip
#
# The bus and rail feeds share no stop_id, trip_id, route_id or service_id, so
# the tables are stacked as they are. shapes.txt is left out: the router never
# reads it and it is most of the file size.
#
# restore_rail.zip (v202510260) only runs weekday service from 2025-10-26, so
# rail trips are routed on 2025-11-05 rather than the 2025-10-15 used for the
# bus-only runs. Both bus feeds run exactly the same trips on the two dates.

suppressPackageStartupMessages(library(data.table))

TABLES <- c("agency", "calendar", "calendar_dates", "routes", "stops",
            "stop_times", "trips")

read_table <- function(zip, name) {
  f <- paste0(name, ".txt")
  if (!f %in% unzip(zip, list = TRUE)$Name) return(NULL)
  x <- fread(cmd = sprintf("unzip -p '%s' '%s'", zip, f),
             colClasses = "character", strip.white = TRUE)
  setnames(x, trimws(names(x)))
  x
}

merge_feed <- function(bus_zip, rail_zip, out_zip) {
  tmp <- file.path(tempdir(), sub("\\.zip$", "", basename(out_zip)))
  dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
  unlink(file.path(tmp, "*.txt"))

  for (tb in TABLES) {
    bus  <- read_table(bus_zip, tb)
    rail <- read_table(rail_zip, tb)
    out  <- rbindlist(list(bus, rail), use.names = TRUE, fill = TRUE)
    fwrite(out, file.path(tmp, paste0(tb, ".txt")))
    message(sprintf("  %-15s bus %8s  rail %7s", tb,
                    format(if (is.null(bus)) 0 else nrow(bus), big.mark = ","),
                    format(if (is.null(rail)) 0 else nrow(rail), big.mark = ",")))
  }

  unlink(out_zip)
  old <- setwd(tmp)
  on.exit(setwd(old))
  zip(normalizePath(file.path(old, out_zip), mustWork = FALSE),
      files = paste0(TABLES, ".txt"), flags = "-q")
}

message("cut_merged.zip")
merge_feed("data/gtfs/cut.zip", "data/gtfs/cut_rail.zip", "data/gtfs/cut_merged.zip")

message("restore_merged.zip")
merge_feed("data/gtfs/restore.zip", "data/gtfs/restore_rail.zip", "data/gtfs/restore_merged.zip")
