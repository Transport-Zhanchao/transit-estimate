# SEPTA service cuts: estimated effects on transit travel time

Prepared from DVRPC household-survey trips routed through
SEPTA's service-cut and restored GTFS feeds.

Companion file: **`trip-level-results.csv`** — one row per surveyed trip, both
scenarios, NA where a trip could not be routed. Everything in this report is an
aggregate of that file.


## 1. Methodology

### Trip sample

Trips come from the DVRPC Household Travel Survey (2012–13) trip file. The
starting filter is: origin and destination both in Pennsylvania, aggregate mode
transit (`MODE_AGG` = 5), a parseable clock time in `DEPART`, a weekday travel
date, and no major or minor holiday. Origins and destinations are Traffic
Analysis Zone centroids from DVRPC's TAZ layer, computed in EPSG:26918 and
returned as lon/lat.

That produces two samples, which are kept apart because they route on different
feeds:

| Sample | Trips | Modes | Feed | Service date |
|---|---|---|---|---|
| Bus / subway / trolley | 1,536 | `MODE` 14, 21, 23 | City Transit | 2025-10-15 |
| Regional Rail | 501 | `MODE` 22 + feeder legs | City Transit + Regional Rail | 2025-11-05 |

Regional Rail trips are assembled by chaining consecutive survey trips across
activity code 19, "change type of transportation," so a journey that walks to a
bus, rides to a station and then takes a train is recognised as one rail journey.
The 501 records are 479 train legs plus 22 bus or subway legs feeding a station.
Those 22 feeder legs also appear in the bus sample, so they appear twice in the
csv under different `sample` values; no aggregate in this report mixes the two.

The two service dates differ because the restored rail feed only begins weekday
service on 2025-10-26. Both City Transit feeds operate identical trip counts on
the two dates, so the samples stay comparable.

### Routing

Each trip is routed on its own, door to door: walk to a stop, wait, ride
(transfers included), walk from the last stop to the destination. The two
scenarios are SEPTA's published cut and restored GTFS feeds, routed identically;
for the rail sample the City Transit and Regional Rail feeds are merged into one
so a trip can transfer between a bus and a train.

**Eight departures per trip.** Each trip is routed eight times, at departures
spanning the reported time ±30 minutes, and the eight results are averaged. The
spacing is 8.5 minutes. That number is deliberate: SEPTA headways cluster on 10,
12 and 15 minutes, so a spacing that divides into those would land every draw on
the same point in the headway cycle and all eight would inherit the same wait.
The 59.5-minute span avoids the same trap at the ends.

This matters more than it sounds. On a single draw the bus median difference
between scenarios is 1.00 minute with a standard deviation of 8.46; after
averaging eight it is 1.86 with a standard deviation of 4.21. A single-departure
design would mostly measure headway luck.

### The quantity reported

Throughout, for each trip:

```
Δ = cut_average_min − restore_average_min
```

Positive means **slower under the cuts**. Both terms are eight-draw means. Where
a trip failed to route under one scenario it has no Δ and is excluded from
aggregates, but the row is kept in the csv with NA.

Peak periods follow SEPTA's Regional Rail fare rule, applied to the trip's own
reported departure time: AM peak 6:00–9:30, PM peak 16:00–19:00, everything else
off-peak.

### Scheduled service ("capacity")

GTFS carries no seat or consist data, so capacity in section 3.2 means
**scheduled service**: weekday trips operated, and stop events (one vehicle
calling at one stop), which is the trip count weighted by how many stops each run
serves. Neither is a seat count; a shortened consist would not show up.

---

## 2. Purpose

SEPTA's 2025 service cuts and their subsequent restoration produced two published
timetables for the same network. The question this analysis asks is narrow and
empirical:

**How much door-to-door travel time did riders lose under the cut timetable
relative to the restored one, and was that loss distributed evenly?**

Three things motivated splitting the answer out by mode and geography rather than
reporting a single average:

1. **Regional Rail and City Transit were cut differently.** Whether that shows up
   in rider travel time is not obvious in advance — a deeper cut to a dense
   timetable can cost less than a shallow cut to a sparse one.
2. **An average across all trips is close to meaningless if the loss is
   concentrated.** A 2-minute mean spread evenly is a nuisance; the same mean
   produced by a small group losing 20 minutes is a different policy problem.
3. **Alternatives matter.** A rider whose train disappears but who can take a
   subway loses very little. One with no second option loses the whole gap.

The analysis is descriptive. It compares two operating plans as SEPTA published
them; it does not estimate a causal effect of the cuts, and it does not model
ridership response, crowding or mode shift.

---

## 3. Results

### 3.1 Bus, subway and trolley

**1,473 of 1,536 trips routed under both scenarios.**

| | n | Cut | Restore | Median Δ | Mean Δ | Median Δ% | Share > 10 min |
|---|---|---|---|---|---|---|---|
| **All bus / subway / trolley** | 1,473 | 33.7 | 31.7 | +1.86 | +2.26 | +6.3% | 4% |
| Bus / trolleybus | 1,041 | 33.7 | 31.7 | +1.96 | +2.38 | +6.5% | 4% |
| Subway / El | 358 | 35.2 | 32.8 | +1.75 | +1.93 | +5.6% | 2% |
| Trolley / light rail | 74 | 27.0 | 27.0 | +1.62 | +2.21 | +6.8% | 4% |

The three surface modes behave almost identically — medians within 0.34 minutes
of each other, and 2–4% of trips losing more than 10 minutes. There is no mode
story inside City Transit.

By time of day, the loss is **worst off-peak and mildest in the AM peak**:

| | n | Cut | Restore | Median Δ | Mean Δ | Median Δ% | Share > 10 min |
|---|---|---|---|---|---|---|---|
| AM peak | 381 | 34.0 | 32.0 | +1.62 | +2.02 | +5.0% | 3% |
| PM peak | 362 | 32.8 | 30.8 | +1.87 | +2.09 | +6.6% | 2% |
| Off-peak | 730 | 34.3 | 31.8 | +2.05 | +2.48 | +6.9% | 5% |

By geography:

| | n | Cut | Restore | Median Δ | Mean Δ | Median Δ% | Share > 10 min |
|---|---|---|---|---|---|---|---|
| Within Philadelphia | 1,176 | 30.5 | 28.5 | +1.78 | +2.04 | +6.8% | 2% |
| Cross-county | 199 | 57.6 | 53.7 | +2.67 | +3.66 | +5.5% | 11% |
| Within one suburban county | 98 | 46.9 | 44.0 | +1.19 | +2.10 | +2.9% | 6% |

Cross-county bus trips lose more than city trips in absolute minutes (+2.67
against +1.78), but they are also nearly twice as long, so in percentage terms
they lose less (+5.5% against +6.8%).

The overall picture for City Transit is a small, broadly even loss: a median
under two minutes, 6.3% of trip time, with 4% of trips losing more than 10
minutes.

### 3.2 Regional Rail — scheduled service

Regional Rail lost **164 of 625 weekday trains, 26%**. Stop events fall by a
similar share (7,404 vs 9,367, -21%), so the cut is a reduction in runs rather than a
reduction in stops per run.

| Line | Cut | Restore | Change | % |
|---|---|---|---|---|
| AIR | 40 | 78 | -38 | -49% |
| CHE | 33 | 40 | -7 | -18% |
| CHW | 27 | 42 | -15 | -36% |
| CYN | 7 | 12 | -5 | -42% |
| FOX | 28 | 41 | -13 | -32% |
| LAN | 42 | 55 | -13 | -24% |
| MED | 42 | 52 | -10 | -19% |
| NOR | 42 | 54 | -12 | -22% |
| PAO | 46 | 64 | -18 | -28% |
| TRE | 44 | 50 | -6 | -12% |
| WAR | 40 | 53 | -13 | -25% |
| WIL | 36 | 43 | -7 | -16% |
| WTR | 34 | 41 | -7 | -17% |
| **TOTAL** | 461 | 625 | -164 | -26% |

The cut is uneven across lines. The Airport line loses nearly half its service
and Cynwyd 42%, while Trenton loses 12% and Wilmington 16%.

By time of day:

| Period | Cut | Restore | Change | % |
|---|---|---|---|---|
| Before 6 | 31 | 45 | -14 | -31% |
| AM peak 6-9 | 85 | 125 | -40 | -32% |
| Midday 9-15 | 131 | 170 | -39 | -23% |
| PM peak 15-19 | 118 | 165 | -47 | -28% |
| Evening 19-24 | 96 | 120 | -24 | -20% |
| **TOTAL** | 461 | 625 | -164 | -26% |

The **AM peak is the deepest cut (−32%)**, and within it the 7 o'clock hour falls
from 50 trains to 29 (−42%). Midday is the shallowest of the daytime bands
(−23%).

City Transit was cut by a similar total share but with the opposite shape —
**midday deepest, AM peak shallowest**:

| Period | Cut | Restore | Change | % |
|---|---|---|---|---|
| Before 6 | 1,282 | 1,457 | -175 | -12% |
| AM peak 6-9 | 2,385 | 3,013 | -628 | -21% |
| Midday 9-15 | 3,457 | 4,758 | -1,301 | -27% |
| PM peak 15-19 | 2,841 | 3,671 | -830 | -23% |
| Evening 19-24 | 1,827 | 2,203 | -376 | -17% |
| **TOTAL** | 11,792 | 15,102 | -3,310 | -22% |

City Transit stop events: 698,085 vs 897,372, -22%.

This opposite shape is the mechanism behind the travel-time results in 3.1 and
3.3: bus riders lose most off-peak because that is where bus service was thinned,
and rail riders lose most in the peak for the same reason.

### 3.3 Regional Rail — travel time change

**442 of 501 trips routed under both scenarios.**

| | n | Cut | Restore | Median Δ | Mean Δ | Median Δ% | Share > 10 min |
|---|---|---|---|---|---|---|---|
| **All Regional Rail trips** | 442 | 60.0 | 54.0 | +3.73 | +4.97 | +8.1% | 19% |
| Train legs | 425 | 60.5 | 54.7 | +3.98 | +5.12 | +8.1% | 19% |
| Feeder bus / subway legs | 17 | 18.8 | 20.4 | +1.53 | +1.27 | +8.5% | 0% |

Rail trips lose roughly twice what bus trips lose, both in minutes (+3.73 against
+1.86 median) and as a share of trip time (+8.1% against +6.3%) — on top of being
nearly twice as long to begin with. The tail is the sharper difference: **19% of
rail trips lose more than 10 minutes against 4% of bus trips**, and 17 rail trips
lose more than 20 minutes. Losses that size come from a connection disappearing,
not from a schedule being retimed.

The 17 feeder legs are a useful internal control. They are bus and subway legs
inside rail journeys, and they behave like the bus sample (+1.53), not like the
trains they connect to.

By time of day, rail runs **opposite to bus** — worst in the AM peak, mildest
off-peak:

| | n | Cut | Restore | Median Δ | Mean Δ | Median Δ% | Share > 10 min |
|---|---|---|---|---|---|---|---|
| AM peak | 183 | 61.6 | 55.3 | +5.37 | +5.93 | +10.1% | 23% |
| PM peak | 154 | 57.9 | 51.1 | +3.08 | +5.03 | +8.4% | 18% |
| Off-peak | 105 | 60.3 | 55.4 | +2.29 | +3.23 | +6.2% | 12% |

By geography:

| | n | Cut | Restore | Median Δ | Mean Δ | Median Δ% | Share > 10 min |
|---|---|---|---|---|---|---|---|
| Cross-county | 259 | 68.8 | 62.2 | +5.98 | +6.54 | +9.2% | 28% |
| Within Philadelphia | 171 | 46.6 | 42.8 | +1.79 | +2.85 | +6.5% | 5% |
| Within one suburban county | 12 | 37.3 | 37.2 | +1.69 | +1.39 | +5.0% | 0% |

#### The loss is concentrated in one group of trips

Splitting both samples on geography and time period together shows the rail
penalty is not a general property of rail:

| Geography | Period | Rail median Δ | Rail n | Non-rail median Δ | Non-rail n |
|---|---|---|---|---|---|
| Cross-county | AM peak | +6.58 | 127 | +2.02 | 58 |
| Cross-county | PM peak | +5.98 | 82 | +3.35 | 54 |
| Cross-county | Off-peak | +2.47 | 50 | +2.73 | 87 |
| Within Philadelphia | AM peak | +2.11 | 53 | +1.50 | 295 |
| Within Philadelphia | PM peak | +1.13 | 71 | +1.63 | 281 |
| Within Philadelphia | Off-peak | +2.42 | 47 | +2.05 | 600 |

In four of these six cells rail and non-rail are within about half a minute of
each other, and in two of them rail does slightly *better*. The penalty appears
only in cross-county peak trips.

Collapsing to that one cell:

| | Regional Rail | Non-rail |
|---|---|---|
| Cross-county, peak | **+6.38** (n=209) | +2.65 (n=112) |
| Everything else | +1.95 (n=233) | +1.79 (n=1,361) |
| All trips | +3.73 (n=442) | +1.86 (n=1,473) |

**That cell is 209 trips, 47% of the rail sample, and it carries the entire
rail-versus-bus difference.** Remove it and the two samples are the same number.
Within it, 31% of rail trips lose more than 10 minutes against 6% of comparable
non-rail trips.

Note that comparable *bus* trips in that cell also do worse than the bus average
(+2.65 against +1.79). The pattern is better described as a penalty on
cross-county peak-hour travel, which Regional Rail happens to carry most of, than
as a penalty on rail as a mode.

### 3.4 Departure timing is a larger source of variation than the cuts

The eight draws for a single trip have a median standard deviation of 4.8 minutes
(bus) and 8.8 (rail), against mean scenario differences of 2.3 and 5.0. The ratio
of effect to noise is about the same in both samples (0.5 and 0.6).

For an individual rider of either mode, **when you leave matters as much as or
more than whether the cuts were in effect**. The scenario effect is real but only
emerges in aggregate; it is not something a single rider could reliably detect on
a given morning.

---

## 4. Limitations

**The two feeds are not a matched pair.** They are separately published
timetables, not one network with service removed. 60 stops are served only under
the cut feed, 302 see more departures under it, and 65% of the cut feed's
departure events have no exact counterpart in the restored feed. The visible
symptom is that about 18% of rail trips and 20% of bus trips come out *faster*
under the cuts. Read the results as a comparison of two operating plans as SEPTA
ran them, not as an isolated causal effect of the cuts. The share coming out
faster is nearly the same in both samples, so this asymmetry does not by itself
produce the rail-versus-bus gap.

**Estimates run high against the survey.** For rail legs the restored-scenario
median is 54.7 minutes against 38 reported and 37.8 from `Model_TravTime`, about
45% higher. The estimates are door to door and include access walking and
waiting, which the other two largely exclude, and suburban TAZ centroids sit
farther from stations than real addresses do. Rank correlation with
`Model_TravTime` is 0.879, so relative comparisons hold even though levels are
inflated. **Treat every number here as a difference between scenarios, not as a
travel time.**

**Origins and destinations are zone centroids, not addresses.** This inflates
access walking, and it does so unevenly: suburban zones are larger, so suburban
trips are penalised more than city trips. Since the headline result is that
suburban cross-county trips lose the most, this bias runs in the same direction
as the finding and cannot be fully separated from it.

**The trips are legs, not journeys.** About a quarter of records end at a
transfer point, so their estimated time is time-to-transfer rather than to a
final destination.

**This is a counterfactual.** 2012–13 origins, destinations and departure times
are projected onto 2025 networks. The trip mix — including how much of the peak
is cross-county commuting — is the 2012–13 mix, not today's.

**Capacity means scheduled service.** Train and trip counts from GTFS say nothing
about consist length or seats, so a cut absorbed by running shorter trains would
not appear in section 3.2.

**Thin cells.** Several breakdowns rest on small counts: 12 rail trips stay within
a single suburban county, 50 rail cross-county trips are off-peak, and the
non-rail cross-county peak cell is 112 trips. Percentages on these move several
points with a handful of trips.

**No behavioural response.** Riders facing a worse trip may retime, change mode or
not travel. None of that is modelled; every trip is held fixed and re-routed.

---

## 5. The trip-level file

`trip-level-results.csv` — 2,037 rows, one per trip per sample, no aggregation.

| Column | Meaning |
|---|---|
| `record_id` | survey trip key |
| `sample` | `bus_subway_trolley` or `regional_rail` |
| `mode` | survey `MODE`: bus / trolleybus, subway / El, trolley / light rail, Regional Rail |
| `o_taz` | origin Traffic Analysis Zone |
| `d_taz` | destination Traffic Analysis Zone |
| `restore_average_min` | eight-draw mean door-to-door travel time, restored feed |
| `cut_average_min` | eight-draw mean door-to-door travel time, cut feed |
| `delta_min` | `cut_average_min − restore_average_min`; positive = slower under the cuts |

`o_taz` / `d_taz` are the DVRPC zone ids the trip was routed between, taken from
the survey trip file. They are the OD pair the travel times refer to: routing
used each zone's centroid, not the respondent's address, so trips sharing an OD
pair share their endpoints exactly. Zone geometry is in `data/taz.geojson`
(field `taz`), which joins to both columns.

Trips that could not be routed are **NA** in the three time columns and kept in
the file:

| Sample | Both | Cut only | Restore only | Neither |
|---|---|---|---|---|
| Bus / subway / trolley | 1,473 | 3 | 13 | 47 |
| Regional Rail | 442 | 1 | 6 | 52 |

A trip fails to route when no itinerary exists within the router's limits under
that feed — typically an origin or destination centroid too far from any served
stop, which is why the failures skew suburban.

The 22 feeder legs described in section 1 appear twice, once under each `sample`,
because they were routed on two different feeds. Filter on `sample` to get either
sample exactly.

