# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

# Descriptive correlates of the cut-vs-restore travel-time change, on the same
# complete-case sample as 11-model-delta.R, plus the plain OLS of delta_min on X.
#
# Input : data/trip_panel.csv          trip x scenario panel (from 10)
# Output: tables/delta-correlates.md   group means, correlations, OLS fit
#
# The OLS slopes equal the panel_fe_min column in tables/model-delta.md
# (tt ~ cut + cut:X | trip is the same model as delta ~ X); it is refit here
# for an R2 on delta itself, and per sample to check the pooled fit.

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
})

trips <- fread("data/trip_panel.csv")[cut == 1]
trips[, `:=`(o_dist_cc_10km = o_dist_cc_km / 10, trip_10km = trip_km / 10)]
x_vars <- c("rail", "o_dist_cc_10km", "trip_10km", "peak", "work_tour",
            "female", "age_65plus", "black", "nonwhite_other", "college_deg",
            "employed", "low_income", "zero_veh_hh")
cc <- trips[complete.cases(trips[, c(x_vars, "delta_min"), with = FALSE])]

# ---- 1. group comparisons (binary X) ---------------------------------------------
summ <- function(d) d[, .(n = .N, mean = mean(delta_min), median = median(delta_min),
                         gt5 = mean(delta_min > 5))]
bin_vars <- setdiff(x_vars, c("o_dist_cc_10km", "trip_10km"))
grp <- rbindlist(lapply(bin_vars, function(v) {
  s1 <- summ(cc[get(v) == 1]); s0 <- summ(cc[get(v) == 0])
  tt <- t.test(cc[get(v) == 1, delta_min], cc[get(v) == 0, delta_min])
  data.table(variable = v,
             n_yes = s1$n, n_no = s0$n,
             mean_yes = s1$mean, mean_no = s0$mean, diff = s1$mean - s0$mean,
             median_yes = s1$median, median_no = s0$median,
             gt5_yes = s1$gt5, gt5_no = s0$gt5, p = tt$p.value)
}))

# ---- 2. continuous X: correlation and quartiles -----------------------------------
cc <- merge(cc, fread("data/trip_panel.csv")[cut == 0, .(sample, record_id, restore_tt = tt_min)],
            by = c("sample", "record_id"))
cont_vars <- c("trip_km", "o_dist_cc_km", "restore_tt")
cor_tab <- rbindlist(lapply(cont_vars, function(v) {
  ct <- cor.test(cc[[v]], cc$delta_min)
  sp <- suppressWarnings(cor.test(cc[[v]], cc$delta_min, method = "spearman"))
  data.table(variable = v, pearson = ct$estimate, p = ct$p.value, spearman = sp$estimate)
}))
quart <- rbindlist(lapply(cont_vars, function(v) {
  q <- cut(cc[[v]], quantile(cc[[v]], 0:4 / 4), include.lowest = TRUE,
           labels = paste0("Q", 1:4))
  cc[, .(range = sprintf("%.1f-%.1f", min(get(v)), max(get(v))), n = .N,
         mean = mean(delta_min), median = median(delta_min), gt5 = mean(delta_min > 5)),
     by = .(q = q)][order(q)][, variable := v]
}))

# ---- 3. OLS of delta on X, pooled and per sample -----------------------------------
fml <- as.formula(paste("delta_min ~", paste(x_vars, collapse = " + ")))
ols_all  <- feols(fml, data = cc, cluster = ~person_id)
fml_s    <- as.formula(paste("delta_min ~", paste(setdiff(x_vars, "rail"), collapse = " + ")))
ols_bus  <- feols(fml_s, data = cc[rail == 0], cluster = ~person_id)
ols_rail <- feols(fml_s, data = cc[rail == 1], cluster = ~person_id)
# Adding baseline (restore) travel time: does trip length matter beyond its minutes?
ols_tt   <- feols(update(fml, . ~ . + I(restore_tt / 10)), data = cc, cluster = ~person_id)

stars <- function(p) fcase(p < .01, "***", p < .05, "**", p < .1, "*", default = "")
cell  <- function(m, term) {
  ct <- coeftable(m)
  if (!term %in% rownames(ct)) return("")
  sprintf("%.3f%s (%.3f)", ct[term, 1], stars(ct[term, 4]), ct[term, 2])
}
terms <- c("(Intercept)", x_vars, "I(restore_tt/10)")
reg <- data.table(term = terms)
for (nm in c("ols_all", "ols_tt", "ols_bus", "ols_rail")) {
  m <- get(nm); reg[, (nm) := vapply(terms, function(t) cell(m, t), "")]
}
fit <- data.table(term = c("N", "persons", "R2", "adj. R2"))
for (nm in c("ols_all", "ols_tt", "ols_bus", "ols_rail")) {
  m <- get(nm)
  fit[, (nm) := c(nobs(m), uniqueN(cc[obs(m), person_id]),
                  sprintf("%.3f", r2(m, "r2")), sprintf("%.3f", r2(m, "ar2")))]
}

# ---- write ---------------------------------------------------------------------------
md_table <- function(dt) {
  c(paste("|", paste(names(dt), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(dt)), collapse = " | "), "|"),
    apply(dt, 1, function(r) paste("|", paste(r, collapse = " | "), "|")))
}
pct <- function(x) sprintf("%.0f%%", 100 * x)
f2  <- function(x) sprintf("%.2f", x)
grp_out <- grp[, .(variable, n_yes, n_no, mean_yes = f2(mean_yes), mean_no = f2(mean_no),
                   diff = sprintf("%+.2f", diff), median_yes = f2(median_yes),
                   median_no = f2(median_no), gt5_yes = pct(gt5_yes), gt5_no = pct(gt5_no),
                   p = sprintf("%.3f", p))]
cor_out <- cor_tab[, .(variable, pearson = f2(pearson), p = sprintf("%.3g", p),
                       spearman = f2(spearman))]
q_out <- quart[, .(variable, q, range, n, mean = f2(mean), median = f2(median), gt5 = pct(gt5))]

lines <- c(
  "# Correlates of the cut-vs-restore travel-time change",
  "",
  "Generated by `scripts/13-describe-delta.R` from `data/trip_panel.csv`.",
  sprintf("Same complete-case sample as `tables/model-delta.md`: %d trips, %d persons.",
          nrow(cc), uniqueN(cc$person_id)),
  "delta = cut minus restore (minutes); gt5 = share of trips with delta > 5 min.",
  "",
  "## Binary covariates (Welch t-test on the mean, trips treated as independent)",
  "", md_table(grp_out), "",
  "## Continuous covariates",
  "", md_table(cor_out), "", md_table(q_out), "",
  "## OLS of delta_min on X (SE clustered by person)",
  "",
  "ols_tt adds baseline (restore) travel time per 10 min. ols_bus / ols_rail fit each sample alone.",
  "\\* p<0.1, \\*\\* p<0.05, \\*\\*\\* p<0.01.",
  "", md_table(rbind(reg, fit))
)
writeLines(lines, "tables/delta-correlates.md")

print(grp_out); print(cor_out); print(q_out); print(rbind(reg, fit))
cat("\nwrote tables/delta-correlates.md\n")
