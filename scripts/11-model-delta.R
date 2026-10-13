# Paths are relative to the project root (where transit-estimate.Rproj lives).
setwd(here::here())

# Regression-based prediction of the cut-vs-restore travel-time change (issue #1).
#
# Input : data/trip_panel.csv     trip x scenario panel (from 10)
# Output: tables/model-delta.md   coefficient tables and fit summaries
#
# Models, all on the same complete-case sample and the same covariates:
#   (0) panel FE    tt_min ~ cut + cut:X | trip       (linear, minutes)
#   (1) ordered logit on the delta category (improved / ~same / worse / much worse)
#   (2) binary logit  on "much worse" (delta > 5 min)
#   (3) multinomial logit on the same four categories, for comparison with (1)
# Standard errors are clustered by person (one person makes several trips).
# Models are unweighted: they describe routed trips, not the regional population.

suppressPackageStartupMessages({
  library(data.table)
  library(MASS)
  library(nnet)
  library(fixest)
  library(sandwich)
  library(lmtest)
})

panel <- fread("data/trip_panel.csv")
trips <- panel[cut == 1]   # one row per trip; delta_min and features are trip-level

# ---- outcome ----------------------------------------------------------------------
# Breaks: +/- 1 minute is treated as no change (well inside the 8-draw noise),
# 5 minutes is roughly the 80th percentile and a change riders would notice.
brks <- c(-Inf, -1, 1, 5, Inf)
lvls <- c("improved", "about_same", "worse", "much_worse")
trips[, delta_cat := factor(cut(delta_min, brks, labels = lvls), levels = lvls, ordered = TRUE)]
trips[, much_worse := as.integer(delta_cat == "much_worse")]

# ---- covariates -------------------------------------------------------------------
x_vars <- c("rail", "o_dist_cc_km", "trip_km", "peak", "work_tour",
            "female", "age_65plus", "black", "nonwhite_other", "college_deg",
            "employed", "low_income", "zero_veh_hh")
trips[, `:=`(o_dist_cc_10km = o_dist_cc_km / 10, trip_10km = trip_km / 10)]
x_vars <- sub("o_dist_cc_km", "o_dist_cc_10km", sub("trip_km", "trip_10km", x_vars))

cc <- trips[complete.cases(trips[, c(x_vars, "delta_min"), with = FALSE])]
cat("trips:", nrow(trips), " complete cases:", nrow(cc),
    " persons:", uniqueN(cc$person_id), "\n\n")
print(cc[, .N, delta_cat][order(delta_cat)][, share := round(N / sum(N), 3)][])

rhs <- paste(x_vars, collapse = " + ")

# ---- (0) panel fixed effects ------------------------------------------------------
pcc <- panel[record_id %in% cc$record_id & sample %in% cc$sample]
pcc <- merge(pcc, cc[, .(sample, record_id, o_dist_cc_10km, trip_10km)],
             by = c("sample", "record_id"))
pcc[, trip_key := paste(sample, record_id)]
fe <- feols(as.formula(paste0("tt_min ~ cut + ",
                              paste0("cut:", x_vars, collapse = " + "), " | trip_key")),
            data = pcc, cluster = ~person_id)

# ---- (1) ordered logit --------------------------------------------------------------
ol <- polr(as.formula(paste("delta_cat ~", rhs)), data = cc, Hess = TRUE)
ol_vc <- vcovCL(ol, cluster = ~person_id)
ol_ct <- coeftest(ol, vcov. = ol_vc)

# ---- (2) binary logit ---------------------------------------------------------------
bl <- glm(as.formula(paste("much_worse ~", rhs)), data = cc, family = binomial)
bl_ct <- coeftest(bl, vcov. = vcovCL(bl, cluster = ~person_id))

# ---- (3) multinomial logit (base = about_same) ------------------------------------
cc[, delta_nom := relevel(factor(as.character(delta_cat), levels = lvls), ref = "about_same")]
ml <- multinom(as.formula(paste("delta_nom ~", rhs)), data = cc, trace = FALSE)
ml_coef <- coef(ml)
ml_se   <- sqrt(diag(vcov(ml)))   # model-based; nnet has no cluster-robust vcov
ml_se   <- matrix(ml_se, nrow = nrow(ml_coef), byrow = TRUE, dimnames = dimnames(ml_coef))

# ---- proportional-odds check --------------------------------------------------------
# Brant-style: fit the three cumulative binary logits separately and compare slopes.
# Big spreads mean the single ordered-logit slope is averaging different effects.
cum_fits <- sapply(2:4, function(k) {
  y <- as.integer(as.integer(cc$delta_cat) >= k)
  coef(glm(as.formula(paste("y ~", rhs)), data = cbind(cc, y = y), family = binomial))[x_vars]
})
colnames(cum_fits) <- paste0(">=", lvls[2:4])

# ---- write tables -------------------------------------------------------------------
stars <- function(p) fcase(p < .01, "***", p < .05, "**", p < .1, "*", default = "")
fmt   <- function(b, se, p) sprintf("%.3f%s (%.3f)", b, stars(p), se)

tab <- data.table(term = x_vars)
tab[, panel_fe_min := {
  ct <- coeftable(fe); r <- paste0("cut:", term)
  fmt(ct[r, 1], ct[r, 2], ct[r, 4])
}]
tab[, ordered_logit := fmt(ol_ct[term, 1], ol_ct[term, 2], ol_ct[term, 4])]
tab[, ordered_OR := sprintf("%.2f", exp(ol_ct[term, 1]))]
tab[, logit_much_worse := fmt(bl_ct[term, 1], bl_ct[term, 2], bl_ct[term, 4])]
tab[, logit_OR := sprintf("%.2f", exp(bl_ct[term, 1]))]

mtab <- data.table(term = x_vars)
for (k in rownames(ml_coef)) {
  b <- ml_coef[k, x_vars]; s <- ml_se[k, x_vars]; p <- 2 * pnorm(-abs(b / s))
  mtab[, (k) := fmt(b, s, p)]
}

md_table <- function(dt) {
  c(paste("|", paste(names(dt), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(dt)), collapse = " | "), "|"),
    apply(dt, 1, function(r) paste("|", paste(r, collapse = " | "), "|")))
}

dist <- cc[, .N, delta_cat][order(delta_cat)][, share := sprintf("%.1f%%", 100 * N / sum(N))]
cutpts <- ol$zeta
lines <- c(
  "# Predicting the cut-vs-restore travel-time change",
  "",
  "Generated by `scripts/11-model-delta.R` from `data/trip_panel.csv` (issue #1).",
  "",
  sprintf("Sample: %d trips with both scenarios routed and complete covariates, %d persons.",
          nrow(cc), uniqueN(cc$person_id)),
  "Standard errors (in parentheses) are clustered by person except in the multinomial model.",
  "\\* p<0.1, \\*\\* p<0.05, \\*\\*\\* p<0.01. Distances are per 10 km.",
  "",
  "## Outcome",
  "",
  "delta = cut minus restore, 8-draw mean travel time (minutes).",
  "",
  md_table(dist),
  "",
  "## Panel FE, ordered logit, binary logit",
  "",
  "- **panel_fe_min**: minutes added by the cut for a one-unit change in X (trip fixed effects;",
  sprintf("  baseline cut effect %.2f min).", coef(fe)["cut"]),
  "- **ordered_logit**: log-odds of being in a worse delta category; OR > 1 = worse hit.",
  "- **logit_much_worse**: log-odds of delta > 5 min.",
  "",
  md_table(tab),
  "",
  sprintf("Ordered logit cutpoints: %s. Residual deviance %.1f, AIC %.1f.",
          paste(sprintf("%s = %.2f", names(cutpts), cutpts), collapse = ", "),
          deviance(ol), AIC(ol)),
  sprintf("Binary logit: AIC %.1f, McFadden pseudo-R2 %.3f.",
          AIC(bl), 1 - bl$deviance / bl$null.deviance),
  sprintf("Panel FE: within R2 %.3f.", fitstat(fe, "wr2")[[1]]),
  "",
  "## Proportional-odds check",
  "",
  "Slopes from the three cumulative binary logits behind the ordered model.",
  "Large differences across columns mean the single ordered-logit slope hides different effects.",
  "",
  md_table(data.table(term = x_vars, round(cum_fits, 3))),
  "",
  "## Multinomial logit (base = about_same, model-based SE)",
  "",
  md_table(mtab)
)
writeLines(lines, "tables/model-delta.md")

cat("\n---- panel FE ----\n");        print(coeftable(fe))
cat("\n---- ordered logit ----\n");   print(ol_ct)
cat("\n---- binary logit ----\n");    print(bl_ct)
cat("\n---- cumulative slopes ----\n"); print(round(cum_fits, 3))
cat("\nwrote tables/model-delta.md\n")
