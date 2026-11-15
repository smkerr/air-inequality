# ==============================================================================
# Air (In)equality in Los Angeles
# Follow-up checks on residual spatial autocorrelation
#
# Script 04 leaves Moran's I at about 0.47 after the spatial error model. This
# script tests three suspected causes:
#   1. Unnormalized weights built from 100 nearest neighbors
#   2. A missing location trend (NO2 is a smooth surface centered on downtown)
#   3. Testing unfiltered instead of filtered residuals for the error model
# Output: data/output/spatial-model-comparison.csv
# ==============================================================================


# Setup ------------------------------------------------------------------------
pacman::p_load(
  caret,       # findCorrelation
  dplyr,       # wrangle data
  glue,        # expressive strings
  here,        # file paths
  sf,          # simple features
  spatialreg,  # spatial regression
  spdep,       # spatial dependency
  units        # unit conversion
)

# Load and prepare data (same steps as script 04) ------------------------------
df <- st_read(here("data/output/los-angeles-air-quality.shp"), quiet = TRUE) |>
  na.omit() |>
  rename(
    "total_pop" = "totl_pp",
    "hispanic" = "hispanc",
    "poverty_status" = "pvrty_s",
    "median_household_income" = "mdn_hs_",
    "income_per_cap" = "incm_p_",
    "median_home_value" = "medn_vl",
    "pct_college" = "pct_cll",
    "avg_air_qual" = "avg_r_q"
  ) |>
  mutate(
    pop_density = as.numeric(set_units(total_pop / st_area(geometry), "1/km2")),
    pct_white = white / total_pop,
    pct_black = black / total_pop,
    pct_asian = asian / total_pop,
    pct_hispanic = hispanic / total_pop,
    poverty_rate = poverty_status / total_pop
  ) |>
  select(-total_pop, -white, -black, -asian, -hispanic, -poverty_status)

# Variables kept after the multicollinearity screen (as in script 04)
cor_matrix <- df |> st_drop_geometry() |> select(-geoid, -name, -avg_air_qual) |> cor()
include_vars <- colnames(cor_matrix)[-findCorrelation(cor_matrix, cutoff = 0.65)]

# Location trend: distance from downtown Los Angeles (km)
downtown <- st_sfc(st_point(c(-118.2437, 34.0522)), crs = st_crs(df))
centroids <- st_centroid(st_geometry(df))
df$dist_downtown <- as.numeric(set_units(st_distance(centroids, downtown)[, 1], "km"))

# Put variables on comparable scales. Home values are in the hundreds of thousands
# while NO2 is around 1e-4 mol/m2, which makes the model's information matrix
# singular. Predictors become z-scores and NO2 is expressed in units of 1e-5 mol/m2.
scale_vars <- c(include_vars, "dist_downtown")
df[scale_vars] <- lapply(st_drop_geometry(df)[scale_vars], function(x) as.numeric(scale(x)))
df$no2 <- df$avg_air_qual * 1e5

formulas <- list(
  base = as.formula(glue("no2 ~ {paste(include_vars, collapse = ' + ')}")),
  with_distance = as.formula(glue("no2 ~ {paste(c(include_vars, 'dist_downtown'), collapse = ' + ')}")),
  log_with_distance = as.formula(glue("log(no2) ~ {paste(c(include_vars, 'dist_downtown'), collapse = ' + ')}"))
)


# Spatial weights --------------------------------------------------------------
idw <- function(nb, p = 2, eps = 1e-4) {
  lapply(nbdists(nb, centroids), function(d) 1 / (d^p + eps))
}
nb_k100 <- knn2nb(knearneigh(centroids, k = 100))
nb_k8   <- knn2nb(knearneigh(centroids, k = 8))
nb_k15  <- knn2nb(knearneigh(centroids, k = 15))
nb_queen <- poly2nb(st_geometry(df), queen = TRUE)

weights <- list(
  "k=100, IDW, binary-style (script 04)" = nb2listw(nb_k100, glist = idw(nb_k100), style = "B"),
  "k=100, IDW, row-standardized"         = nb2listw(nb_k100, glist = idw(nb_k100), style = "W"),
  "k=15, IDW, row-standardized"          = nb2listw(nb_k15, glist = idw(nb_k15), style = "W"),
  "k=8, row-standardized"                = nb2listw(nb_k8, style = "W"),
  "Queen contiguity, row-standardized"   = nb2listw(nb_queen, style = "W", zero.policy = TRUE)
)


# Compare weights and specifications -------------------------------------------
moran_i <- function(x, lw) unname(moran.test(x, lw, zero.policy = TRUE)$estimate[1])

results <- list()
for (w_name in names(weights)) {
  lw <- weights[[w_name]]
  # Binary-style weights make the spatial error model singular (script 04 fails
  # on the lag model for the same reason), so only compute eigenvalues otherwise
  use_sem <- !grepl("binary", w_name)
  ctrl <- if (use_sem) list(pre_eig = eigenw(lw, quiet = TRUE)) else NULL
  for (f_name in names(formulas)) {
    f <- formulas[[f_name]]
    ols <- lm(f, data = df)
    row <- data.frame(
      weights = w_name, specification = f_name,
      moran_ols = moran_i(residuals(ols), lw),
      lambda = NA_real_, moran_sem_raw = NA_real_, moran_sem_filtered = NA_real_,
      aic_ols = AIC(ols), aic_sem = NA_real_, nagelkerke_r2 = NA_real_
    )
    sem <- if (use_sem) tryCatch(
      errorsarlm(f, data = df, listw = lw, zero.policy = TRUE, control = ctrl),
      error = function(e) { message("SEM failed: ", conditionMessage(e)); NULL }
    ) else NULL
    if (!is.null(sem)) {
      e <- residuals(sem)
      row$lambda <- unname(sem$lambda)
      row$moran_sem_raw <- moran_i(e, lw)
      # Filtered residuals remove the error structure the model already estimates
      row$moran_sem_filtered <- moran_i(e - sem$lambda * lag.listw(lw, e, zero.policy = TRUE), lw)
      row$aic_sem <- AIC(sem)
      row$nagelkerke_r2 <- unname(summary(sem, Nagelkerke = TRUE)$NK)
    }
    results[[length(results) + 1]] <- row
    message("done: ", w_name, " | ", f_name)
  }
}
results <- bind_rows(results)
print(results, digits = 3)
write.csv(results, here("data/output/spatial-model-comparison.csv"), row.names = FALSE)


# Lagrange multiplier tests and richer models (best weights, with distance) ----
lw_best <- weights[["k=8, row-standardized"]]
f_best <- formulas[["with_distance"]]
print(lm.LMtests(lm(f_best, data = df), lw_best, test = c("LMerr", "LMlag", "RLMerr", "RLMlag")))

ctrl_best <- list(pre_eig = eigenw(lw_best, quiet = TRUE))
models <- list(
  OLS  = lm(f_best, data = df),
  SEM  = errorsarlm(f_best, data = df, listw = lw_best, control = ctrl_best),
  SAR  = lagsarlm(f_best, data = df, listw = lw_best, control = ctrl_best),
  SDEM = errorsarlm(f_best, data = df, listw = lw_best, etype = "emixed", control = ctrl_best),
  SDM  = lagsarlm(f_best, data = df, listw = lw_best, type = "mixed", control = ctrl_best)
)
cat("\nAIC by model (k=8, row-standardized, with distance to downtown)\n")
print(sapply(models, AIC))
cat("\nMoran's I on residuals by model\n")
print(sapply(models, function(m) moran_i(residuals(m), lw_best)))
cat("\nSpatial error model with distance to downtown\n")
print(summary(models$SEM, Nagelkerke = TRUE))

# Do the conclusions survive? Coefficients with and without the distance term ---
coef_table <- function(m, label) {
  co <- if (inherits(m, "lm")) summary(m)$coefficients else summary(m)$Coef
  data.frame(model = label, term = rownames(co), estimate = co[, 1], std_error = co[, 2], p_value = co[, 4])
}
sem_base <- errorsarlm(formulas$base, data = df, listw = lw_best, control = ctrl_best)
coefs <- bind_rows(
  coef_table(lm(formulas$base, data = df), "OLS, base"),
  coef_table(sem_base, "SEM, base"),
  coef_table(lm(f_best, data = df), "OLS, with distance"),
  coef_table(models$SEM, "SEM, with distance")
)
rownames(coefs) <- NULL
print(coefs, digits = 3)
write.csv(coefs, here("data/output/spatial-model-coefficients.csv"), row.names = FALSE)
