# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

# Histograms for the cut vs restore comparison.
# Output: figures/*.png

suppressPackageStartupMessages({library(data.table); library(ggplot2)})

bus <- fread("data/transit_simple_estimates.csv")[
  !is.na(tt_cut_mean_min) & !is.na(tt_restore_mean_min)]
bus[, `:=`(delta = tt_cut_mean_min - tt_restore_mean_min, sample = "Bus / subway / trolley")]

rail <- fread("data/transit_regional_rail_estimates.csv")[
  !is.na(tt_cut_mean_min) & !is.na(tt_restore_mean_min)]
rail[, `:=`(delta = tt_cut_mean_min - tt_restore_mean_min, sample = "Regional Rail")]
rail[, geo := fifelse(o_county == 42101 & d_county == 42101, "Within Philadelphia",
              fifelse(o_county != d_county, "Suburb <-> city / cross-county",
                      "Within one suburban county"))]

both <- rbindlist(list(
  bus [, .(sample, delta, cut = tt_cut_mean_min, restore = tt_restore_mean_min,
           sd_cut = tt_cut_sd_min)],
  rail[, .(sample, delta, cut = tt_cut_mean_min, restore = tt_restore_mean_min,
           sd_cut = tt_cut_sd_min)]))

theme_set(theme_minimal(base_size = 13))
save_fig <- function(p, file, w = 9, h = 5) {
  ggsave(file.path("figures", file), p, width = w, height = h, dpi = 150)
  message("  ", file)
}

# 1. how much slower each trip is under the cuts
save_fig(
  ggplot(both[delta > -30 & delta < 40], aes(delta)) +
    geom_histogram(binwidth = 1, fill = "#3b6ea5", colour = NA) +
    geom_vline(xintercept = 0, colour = "grey30", linetype = "dashed") +
    facet_wrap(~sample, scales = "free_y") +
    labs(title = "Extra door-to-door minutes under the service cuts",
         subtitle = "cut minus restore, averaged over eight departure times; dashed line = no change",
         x = "Minutes slower under the cuts", y = "Trips"),
  "01-delta-bus-vs-rail.png")

# 2. the travel time distributions themselves
long <- melt(both, id.vars = "sample", measure.vars = c("cut", "restore"),
             variable.name = "scenario", value.name = "minutes")
save_fig(
  ggplot(long[minutes < 150], aes(minutes, fill = scenario)) +
    geom_histogram(binwidth = 5, position = "identity", alpha = 0.55, colour = NA) +
    facet_wrap(~sample, scales = "free_y") +
    scale_fill_manual(values = c(cut = "#c1462f", restore = "#3b6ea5")) +
    labs(title = "Door-to-door travel time, both scenarios",
         subtitle = "eight-draw mean per trip",
         x = "Minutes", y = "Trips", fill = NULL),
  "02-traveltime-distributions.png")

# 3. spread across the eight departure draws for a single trip
save_fig(
  ggplot(both[sd_cut < 30], aes(sd_cut)) +
    geom_histogram(binwidth = 0.5, fill = "#5c8a5c", colour = NA) +
    facet_wrap(~sample, scales = "free_y") +
    labs(title = "How much a trip's travel time moves with its departure time",
         subtitle = "standard deviation across the eight draws, cut scenario",
         x = "Within-trip standard deviation (minutes)", y = "Trips"),
  "03-departure-time-noise.png")

# 4. rail: who absorbs the loss
save_fig(
  ggplot(rail[delta > -25 & delta < 40 & geo != "Within one suburban county"], aes(delta)) +
    geom_histogram(binwidth = 2, fill = "#8a6d3b", colour = NA) +
    geom_vline(xintercept = 0, colour = "grey30", linetype = "dashed") +
    facet_wrap(~geo, scales = "free_y") +
    labs(title = "Regional Rail: extra minutes by trip geography",
         subtitle = "cut minus restore, eight-draw means",
         x = "Minutes slower under the cuts", y = "Trips"),
  "04-rail-by-geography.png")

message("bus n = ", nrow(bus), " | rail n = ", nrow(rail))
