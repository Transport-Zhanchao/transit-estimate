# Who lost the most time under the SEPTA cuts?

Correlates of the cut-vs-restore travel-time change among DVRPC Household Travel
Survey transit trips.


## Summary

- **Where and how far you travel predicts the loss.** Trip
  length and riding Regional Rail are the only predictors that hold up in every
  specification. Each additional 10 km of trip adds about **1.8 minutes** of
  extra travel time under the cuts. A Regional Rail trip loses about **1.2 minutes more** than a City Transit trip of the same length.
- **No demographic variable predicts the loss once trip** 
  This covers gender, age 65+, race, education, employment, low income
  and zero-vehicle households. None of their coefficients is significant at 5% , and all are under half a minute.
- **Some raw gaps run the opposite way to the usual equity concern.**
  Zero-vehicle, low-income and Black respondents lose *less* time on average
  (0.6–0.9 minutes less), but because their trips are shorter and are
  mostly City Transit rather than Regional Rail. Once trip length and mode are
  controlled, the gap disappears.
- **The model explains little of the variation.** R² is 0.11. 


## 1. Question and outcome

For each survey trip, the outcome is:

```
delta_min = cut_average_min − restore_average_min
```

Both terms are eight-departure averages from the routing step (see section 1). 
A positive value means the trip is **slower under the cut timetable**. 
"Larger delta" in this report means "lost more time to the
cuts."

The question: **which trip and traveler characteristics are associated with a larger delta?**

This is descriptive. The models describe which riders' trips were hit harder.
They do not estimate a causal effect of demographics. Riders also did not
choose their trips in response to the cuts: the trips are 2012–13 survey trips
routed on 2025 timetables.


## 2. Data

| Step | Trips | Persons |
|---|---|---|
| Survey transit trips in the two samples (bus/subway/trolley + Regional Rail) | 2,037 | 1,001 |
| Routed under both scenarios | 1,915 | — |
| Complete covariates (**model sample**) | **1,659** | **811** |

- **Bus / subway / trolley**: 1,255 trips. **Regional Rail**: 404 trips.
- Survey attributes come from the household, person and trip files. They are
  joined on `RECORD_ID`, `HH_ID + PERSON_NUM` and `HH_ID` respectively
  (`scripts/09-join-hhts.R`), and every trip matched.
- Trip geography uses the routed origin and destination coordinates: straight-line
  trip length, and distance from the origin to City Hall
  (`scripts/10-build-panel.R`).
- The 256 trips dropped for missing covariates are mostly missing income
  (5.6%), license or employment (about 4% each), or race (3.7%).
- The models are **unweighted**. They describe routed survey trips, not the
  regional population of transit trips.

Covariates:

| Variable | Definition |
|---|---|
| `rail` | Trip is in the Regional Rail sample |
| `trip_10km` | Straight-line origin–destination distance, per 10 km |
| `o_dist_cc_10km` | Origin distance to City Hall, per 10 km |
| `peak` | Departure in SEPTA peak (6:00–9:30, 16:00–19:00) |
| `work_tour` | Home-based work tour |
| `female`, `age_65plus` | Person attributes |
| `black`, `nonwhite_other` | Race; reference = white |
| `college_deg` | Bachelor's degree or higher |
| `employed` | Employed |
| `low_income` | Household income under $35,000 |
| `zero_veh_hh` | Household owns no vehicle |


## 3. What correlates with the loss

### 3.1 Raw comparisons

Mean delta (minutes) by group. *gt5* is the share of trips losing more than 5
minutes. The p-values come from Welch t-tests that treat trips as independent,
so they overstate precision. Section 4 corrects for that.

| Group | n (yes / no) | Mean Δ yes | Mean Δ no | Diff | gt5 yes | gt5 no | p |
|---|---|---|---|---|---|---|---|
| Regional Rail | 404 / 1,255 | 5.10 | 2.31 | **+2.79** | 44% | 16% | <0.001 |
| Peak departure | 943 / 716 | 3.28 | 2.61 | +0.66 | 25% | 20% | 0.009 |
| College degree | 993 / 666 | 3.25 | 2.60 | +0.65 | 24% | 21% | 0.010 |
| Employed | 1,075 / 584 | 3.19 | 2.63 | +0.56 | 25% | 19% | 0.029 |
| Work tour | 883 / 776 | 3.14 | 2.82 | +0.33 | 25% | 20% | 0.194 |
| Age 65+ | 330 / 1,329 | 3.00 | 2.99 | +0.01 | 22% | 23% | 0.977 |
| Female | 901 / 758 | 2.94 | 3.05 | −0.11 | 23% | 23% | 0.680 |
| Other non-white | 119 / 1,540 | 2.81 | 3.01 | −0.20 | 20% | 23% | 0.696 |
| Low income | 565 / 1,094 | 2.58 | 3.20 | **−0.63** | 19% | 25% | 0.015 |
| Zero-vehicle HH | 689 / 970 | 2.49 | 3.35 | **−0.85** | 18% | 27% | 0.001 |
| Black | 401 / 1,258 | 2.31 | 3.21 | **−0.90** | 18% | 25% | 0.001 |

The continuous trip measures show a clear gradient:

| | Pearson r | Spearman ρ |
|---|---|---|
| Trip length (km) | 0.31 | 0.29 |
| Baseline (restore) travel time | 0.21 | 0.25 |
| Origin distance to City Hall | 0.16 | 0.14 |

By trip-length quartile:

| Trip length | n | Mean Δ | Median Δ | gt5 |
|---|---|---|---|---|
| Q1: 0–2.1 km | 415 | 1.50 | 1.23 | 7% |
| Q2: 2.2–4.8 km | 415 | 1.99 | 1.90 | 13% |
| Q3: 4.8–11.1 km | 414 | 3.08 | 2.71 | 26% |
| Q4: 11.1–50.7 km | 415 | 5.40 | 4.32 | 46% |

Trips in the top quartile are more than six times as likely as trips in the
bottom quartile to lose more than 5 minutes.

### 3.2 Why the demographic gaps appear

| Group | Regional Rail share (yes / no) | Median trip km (yes / no) | Origin in Philadelphia (yes / no) |
|---|---|---|---|
| Zero-vehicle HH | 5% / 38% | 3.3 / 7.6 | 88% / 74% |
| Low income | 5% / 34% | 3.9 / 6.2 | 87% / 76% |
| Black | 8% / 30% | 4.3 / 5.2 | 90% / 77% |
| Employed | 34% / 7% | 6.5 / 3.3 | 77% / 86% |
| College degree | 34% / 11% | 5.7 / 4.5 | 78% / 83% |

The cuts cost more on long trips and on Regional Rail. 


## 4. Regression results

### 4.1 Main table

Linear models of `delta_min` (minutes). Standard errors are clustered by person
and shown in parentheses. \* p<0.1, \*\* p<0.05, \*\*\* p<0.01.

- **(1) Pooled**: both samples together. It is identical to the panel model
  `tt ~ cut + cut:X | trip` in `tables/model-delta.md`.
- **(2) + baseline time**: adds restore travel time, per 10 minutes.
- **(3) Bus / subway / trolley only.**
- **(4) Regional Rail only.**

| | (1) Pooled | (2) + baseline time | (3) Bus/subway/trolley | (4) Regional Rail |
|---|---|---|---|---|
| Regional Rail | **1.219\*\*\*** (0.386) | **0.994\*\*** (0.398) | | |
| Trip length (per 10 km) | **1.785\*\*\*** (0.319) | **2.870\*\*\*** (0.552) | **1.661\*\*\*** (0.434) | **1.760\*\*\*** (0.453) |
| Origin to City Hall (per 10 km) | 0.082 (0.277) | 0.242 (0.277) | 0.121 (0.351) | 0.007 (0.440) |
| Baseline travel time (per 10 min) | | **−0.442\*\*\*** (0.168) | | |
| Peak departure | 0.207 (0.272) | 0.090 (0.272) | −0.306 (0.247) | **2.798\*\*\*** (0.999) |
| Work tour | −0.458 (0.384) | −0.520 (0.379) | −0.553 (0.375) | −0.206 (1.085) |
| Female | 0.134 (0.248) | 0.130 (0.248) | 0.400 (0.252) | −0.764 (0.676) |
| Age 65+ | 0.417 (0.334) | 0.351 (0.347) | 0.277 (0.310) | 1.202 (1.116) |
| Black | −0.322 (0.291) | −0.307 (0.288) | −0.531\* (0.291) | 0.523 (0.962) |
| Other non-white | 0.049 (0.432) | −0.024 (0.423) | −0.243 (0.373) | 1.123 (1.669) |
| College degree | 0.193 (0.292) | 0.093 (0.299) | −0.117 (0.288) | 0.848 (0.964) |
| Employed | −0.024 (0.376) | 0.005 (0.376) | 0.345 (0.354) | −2.898\* (1.591) |
| Low income | 0.274 (0.324) | 0.264 (0.328) | 0.124 (0.319) | 1.631 (1.151) |
| Zero-vehicle HH | 0.240 (0.285) | 0.217 (0.289) | 0.171 (0.291) | 1.271 (1.016) |
| Intercept | 1.017\*\* (0.464) | 2.090\*\*\* (0.539) | 1.382\*\*\* (0.450) | 2.249 (1.869) |
| N trips | 1,659 | 1,659 | 1,255 | 404 |
| N persons | 811 | 811 | 606 | 205 |
| R² | 0.109 | 0.118 | 0.045 | 0.123 |
| Adj. R² | 0.102 | 0.111 | 0.036 | 0.096 |

**Reading the table.**

- **Trip length is the dominant predictor.** Every additional 10 km adds 1.7–1.8
  minutes in every sample. The slope is almost the same for City Transit (1.66)
  and Regional Rail (1.76), so the length effect is not a by-product of the rail
  trips.
- **Regional Rail adds about 1.2 minutes on top of trip length.** This matches
  the depth of the cut: 26% of weekday trains, against small changes on City
  Transit.
- **Peak only matters on Regional Rail.** There, a peak departure loses about 2.8
  more minutes than an off-peak one, consistent with the roughly 32% cut to
  AM-peak trains in `report/report.md` §3.2. For City Transit the peak effect is
  near zero, and the pooled coefficient averages the two.
- **Baseline time (2): longer scheduled times mean smaller losses at a given
  distance.** With trip length held fixed, a trip that already takes longer
  under the restored timetable loses less. A plausible reading is that slow trips
  for their distance are dominated by walking and transfers, which the cuts do
  not change, rather than by headway. Adding baseline time also raises the
  length coefficient to 2.9, because the two are correlated.
- **None of the eight demographic variables is significant at 5% in any model.**
  Two coefficients reach 10%: Black in the bus model (−0.53 minutes) and employed
  in the rail model (−2.9, with a wide interval). Given 32 demographic
  coefficients across the four models, a few at 10% is what chance alone would
  produce.

### 4.2 Effects on "noticeably worse" trips

We also fits two other models:

- a binary logit for whether a trip loses **more than 5 minutes** (23% of
  trips);
- an ordered logit over four outcomes: improved (Δ < −1 min), about the same,
  worse (1–5 min), and much worse (> 5 min).

Odds ratios, with person-clustered SEs:

| | Binary logit: Δ > 5 min (OR) | Ordered logit (OR) |
|---|---|---|
| Regional Rail | **2.22\*\*\*** | **1.62\*\*\*** |
| Trip length (per 10 km) | **2.11\*\*\*** | **1.87\*\*\*** |
| Origin to City Hall (per 10 km) | **1.30\*\*\*** | 1.07 |
| Peak | 0.97 | 0.97 |
| Age 65+ | 1.30 | 1.17 |
| Low income | 1.09 | 1.17 |
| Zero-vehicle HH | 1.09 | 1.04 |
| Black | 0.97 | 0.96 |
| *(other demographics)* | 0.89–1.07, none significant | 0.87–1.09, none significant |
| McFadden pseudo-R² | 0.132 | — |

The story is the same as in the linear models. Each additional 10 km roughly
doubles the odds of losing more than 5 minutes, and so does riding Regional
Rail. Two points are new:

- **Origin distance from Center City matters for the tail only.** It does not
  shift the average loss in (1), but it raises the odds of a loss above 5
  minutes. Suburban origins are where frequency was thinnest to begin with, so
  a cut leaves the longest gaps there.
- **The ordered model's proportional-odds assumption does not hold for rail
  and trip length.** Their effects are concentrated at the "much worse"
  threshold: the rail slope is 0.33, 0.16 and 0.80 across the three cumulative
  splits. Treat the binary logit as the more faithful summary. Low income has its
  largest slope at the lowest split (0.49): low-income trips are less likely to
  be *faster* under the cuts. That effect is not significant in the multinomial
  model (p < 0.1 only).


## 5. Robustness: repeat trips by the same person

84% of trips belong to someone with more than one trip in the sample, and
person fixed effects explain 46% of the variance in delta among multi-trip
persons. In practice, people repeat the same commute. Clustering by person
handles this for the standard errors. Clustered SEs are within 20% of the
naive ones, so the inference above is not fragile.

As a stricter check, `scripts/12-check-repeat-trips.R` fits the binary logit
500 times, each time on **one randomly chosen trip per person** (about 811
trips):

| | Median coefficient | Share of draws with p < 0.05 |
|---|---|---|
| Regional Rail | 0.880 | **100%** |
| Trip length | 0.634 | **100%** |
| Origin to City Hall | 0.163 | 24% |
| Age 65+ | 0.145 | 1% |
| Low income | 0.136 | 1% |
| Zero-vehicle HH | −0.062 | 0% |
| Black | −0.136 | 1% |
| Every other covariate | — | ≤ 1% |

Only Regional Rail and trip length survive. The origin-distance tail effect
from 4.2 holds in a quarter of the draws, so it should be treated as
suggestive.


## 6. Caveats

1. **Low explanatory power.** R² is about 0.11 pooled and 0.05 within City
   Transit. These covariates are useful for describing *which kinds of trips*
   were hit harder. They are not useful for predicting an individual trip's loss.
2. **Unweighted.** Survey weights (`P_WEIGHT`, `CompositeWeight`) are carried in
   `data/trip_panel.csv` but not used. Population-level statements, such as "X%
   of low-income transit trips lose more than 5 minutes," would need them.
3. **Missing covariates.** Dropping 256 routed trips (13%) for missing data could
   bias the demographic estimates. It is mostly
   income non-response.
4. **Straight-line distance.** Trip length is straight-line, so it understates detours. That probably biases the length coefficient toward zero.


## 7. Conclusion

The cut timetable's cost fell on **long trips and Regional Rail trips**,
especially rail trips in the peak. Who made the trip did not matter once those
are held fixed. Zero-vehicle, low-income and Black riders lost slightly *less*
time on average, because their trips are shorter, city-based bus and subway
trips. This is a statement about **minutes per trip**, though. It says nothing
about the burden relative to income, the lack of alternatives when a trip does
get worse, or how often these riders depend on transit. The data here cannot
address those, so the result should not be read as "the cuts were equitable."