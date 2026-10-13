# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

# Does one person making several trips drive the results in 11?
#
# Input : data/trip_panel.csv
# Output: tables/repeat-trips-check.md
#
# Four checks on the binary logit (delta > 5 min) and the ordered logit:
#   1. how trips are spread across persons, and how much of the variance in
#      delta sits between persons (intra-class correlation)
#   2. naive vs person-clustered standard errors
#   3. person-weighted fit: each trip weighted 1 / (trips by that person), so
#      every person counts once in total
#   4. one-trip-per-person: draw one trip per person at random, refit, repeat

suppressPackageStartupMessages({
  library(data.table)
  library(MASS)
  library(fixest)
  library(sandwich)
  library(lmtest)
})
set.seed(20261006)

trips <- fread("data/trip_panel.csv")[cut == 1]
brks <- c(-Inf, -1, 1, 5, Inf)
lvls <- c("improved", "about_same", "worse", "much_worse")
trips[, delta_cat := factor(cut(delta_min, brks, labels = lvls), levels = lvls, ordered = TRUE)]
trips[, much_worse := as.integer(delta_cat == "much_worse")]
trips[, `:=`(o_dist_cc_10km = o_dist_cc_km / 10, trip_10km = trip_km / 10)]

x_vars <- c("rail", "o_dist_cc_10km", "trip_10km", "peak", "work_tour",
            "female", "age_65plus", "black", "nonwhite_other", "college_deg",
            "employed", "low_income", "zero_veh_hh")
cc <- trips[complete.cases(trips[, c(x_vars, "delta_min"), with = FALSE])]
cc[, n_trips := .N, person_id]
cc[, w_person := 1 / n_trips]
f_bin <- as.formula(paste("much_worse ~", paste(x_vars, collapse = " + ")))
f_ord <- as.formula(paste("delta_cat ~",  paste(x_vars, collapse = " + ")))

# ---- 1. structure -------------------------------------------------------------------
per_person <- cc[, .(n = .N), person_id][, .(persons = .N), by = .(trips = pmin(n, 6))]
setorder(per_person, trips)
per_person[, trips := fifelse(trips == 6, "6+", as.character(trips))]
share_multi <- cc[n_trips > 1, .N] / nrow(cc)

icc_fit <- feols(delta_min ~ 1 | person_id, data = cc[n_trips > 1])
icc_raw <- 1 - sum(resid(icc_fit)^2) / sum((cc[n_trips > 1, delta_min] -
                                            mean(cc[n_trips > 1, delta_min]))^2)
icc_x <- feols(as.formula(paste("delta_min ~", paste(x_vars, collapse = " + "))),
               data = cc[n_trips > 1])
icc_x_fe <- feols(as.formula(paste("delta_min ~", paste(x_vars, collapse = " + "),
                                   "| person_id")), data = cc[n_trips > 1])
cc[, much_worse_any := max(much_worse), person_id]
# How alike are a person's trips in the binary outcome?
pair_agree <- cc[n_trips > 1, .(p = mean(much_worse), n = .N), person_id][
  , .(within_person_all_same = mean(p %in% c(0, 1)))]
# Expected share all-same if trips were independent with the overall rate
p0 <- mean(cc$much_worse)
exp_same <- cc[n_trips > 1, .(n = .N), person_id][, mean(p0^n + (1 - p0)^n)]

# ---- 2-3. naive vs clustered vs person-weighted -----------------------------------
bl   <- glm(f_bin, data = cc, family = binomial)
bl_w <- suppressWarnings(glm(f_bin, data = cc, family = binomial, weights = w_person))
ol   <- polr(f_ord, data = cc, Hess = TRUE)
ol_w <- suppressWarnings(polr(f_ord, data = cc, Hess = TRUE, weights = w_person))

se_naive <- sqrt(diag(vcov(bl)))[x_vars]
se_cl    <- sqrt(diag(vcovCL(bl, cluster = ~person_id)))[x_vars]
ct_w     <- coeftest(bl_w, vcov. = vcovCL(bl_w, cluster = ~person_id))
ol_ct    <- coeftest(ol,   vcov. = vcovCL(ol,   cluster = ~person_id))
ol_w_ct  <- coeftest(ol_w, vcov. = vcovCL(ol_w, cluster = ~person_id))

# ---- 4. one trip per person, repeated ---------------------------------------------
B <- 500
draws <- rbindlist(lapply(seq_len(B), function(b) {
  s <- cc[cc[, .I[sample.int(.N, 1)], person_id]$V1]
  m <- glm(f_bin, data = s, family = binomial)
  ct <- summary(m)$coefficients
  o <- tryCatch(coef(summary(polr(f_ord, data = s, Hess = TRUE)))[x_vars, 1:2],
                error = function(e) matrix(NA, length(x_vars), 2, dimnames = list(x_vars)))
  data.table(draw = b, term = x_vars, b_bin = ct[x_vars, 1], p_bin = ct[x_vars, 4],
             b_ord = o[, 1], p_ord = 2 * pnorm(-abs(o[, 1] / o[, 2])))
}))
draw_sum <- draws[, .(b_bin_median = median(b_bin),
                      b_bin_p05 = quantile(b_bin, .05), b_bin_p95 = quantile(b_bin, .95),
                      share_p_lt_05 = mean(p_bin < .05),
                      b_ord_median = median(b_ord, na.rm = TRUE),
                      share_p_ord_lt_05 = mean(p_ord < .05, na.rm = TRUE)), term]

# ---- write ------------------------------------------------------------------------
md_table <- function(dt) {
  c(paste("|", paste(names(dt), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(dt)), collapse = " | "), "|"),
    apply(dt, 1, function(r) paste("|", paste(r, collapse = " | "), "|")))
}
pstar <- function(p) fcase(p < .01, "***", p < .05, "**", p < .1, "*", default = "")

cmp <- data.table(
  term          = x_vars,
  bin_all       = sprintf("%.3f", coef(bl)[x_vars]),
  se_naive      = sprintf("%.3f", se_naive),
  se_clustered  = sprintf("%.3f", se_cl),
  se_ratio      = sprintf("%.2f", se_cl / se_naive),
  bin_person_wt = sprintf("%.3f%s", ct_w[x_vars, 1], pstar(ct_w[x_vars, 4])),
  ord_all       = sprintf("%.3f%s", ol_ct[x_vars, 1], pstar(ol_ct[x_vars, 4])),
  ord_person_wt = sprintf("%.3f%s", ol_w_ct[x_vars, 1], pstar(ol_w_ct[x_vars, 4]))
)
ds <- draw_sum[, .(term,
                   bin_median = sprintf("%.3f", b_bin_median),
                   bin_90pct_range = sprintf("[%.3f, %.3f]", b_bin_p05, b_bin_p95),
                   share_draws_p_lt_05 = sprintf("%.0f%%", 100 * share_p_lt_05),
                   ord_median = sprintf("%.3f", b_ord_median),
                   ord_share_draws_p_lt_05 = sprintf("%.0f%%", 100 * share_p_ord_lt_05))]

lines <- c(
  "# Repeat trips by the same person",
  "",
  "Generated by `scripts/12-check-repeat-trips.R`. Same sample and covariates as `tables/model-delta.md`.",
  "",
  "## How trips are spread across persons",
  "",
  sprintf("%d trips from %d persons; %.0f%% of trips belong to someone with more than one trip.",
          nrow(cc), uniqueN(cc$person_id), 100 * share_multi),
  "",
  md_table(per_person),
  "",
  sprintf("Among persons with 2+ trips, person fixed effects explain %.0f%% of the variance in delta_min.",
          100 * icc_raw),
  sprintf("After the trip covariates, adding person fixed effects lifts R2 from %.3f to %.3f.",
          r2(icc_x, "r2"), r2(icc_x_fe, "r2")),
  sprintf("Share of multi-trip persons whose trips are all much_worse or all not: %.0f%% (%.0f%% expected if independent).",
          100 * pair_agree$within_person_all_same, 100 * exp_same),
  "",
  "## All trips vs person-weighted",
  "",
  "bin = binary logit (delta > 5 min); ord = ordered logit. Person-weighted fits give each trip",
  "weight 1 / (trips by that person), so every person counts once. se_ratio = clustered / naive SE.",
  "\\* p<0.1, \\*\\* p<0.05, \\*\\*\\* p<0.01 (clustered SE). Stars on ord_person_wt are not reliable:",
  "polr treats the fractional weights as frequency weights, which understates its SEs; use the",
  "one-trip-per-person draws below for significance instead.",
  "",
  md_table(cmp),
  "",
  sprintf("## One trip per person (%d random draws, ~%d trips each)", B, uniqueN(cc$person_id)),
  "",
  md_table(ds)
)
writeLines(lines, "tables/repeat-trips-check.md")
cat(lines, sep = "\n")
