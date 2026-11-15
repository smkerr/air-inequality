# ==============================================================================
# Air (In)equality in Los Angeles
# 13 May 2024
# ==============================================================================


# Original analysis. Its binary-style, 100-neighbor weights make the spatial lag
# model fail and inflate the apparent demographic effects. See
# 04b-spatial-model-checks.R for the sensitivity checks that replace its conclusions.


# Setup ------------------------------------------------------------------------
# Load dependencies
pacman::p_load(
  caret,       # classification & regression training
  dplyr,       # wrangle data
  ggplot2,     # plots
  glue,        # expressive strings
  here,        # file paths
  purrr,       # functional programming
  scales,      # plot scales
  sf,          # simple features
  spatialreg,  # spatial regression
  spdep,       # spatial dependency
  units        # unit conversion
)

# Load data
df <- st_read(here("data/output/los-angeles-air-quality.shp")) |> 
  na.omit() |> # remove observations with missing data
  rename( # restore variable names
    "total_pop" =  "totl_pp",
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
  select(-total_pop, -white, -black, -asian, -hispanic, -poverty_status) |> 
  relocate(c(avg_air_qual, geometry), .after = everything())

# Add IDs to rows
row.names(df) <- df$geoid


# Check for multicollinearity --------------------------------------------------
cor_matrix <- df |> 
  st_drop_geometry() |> 
  select(-geoid, -name, -avg_air_qual) |> 
  cor() 
cor_matrix
multicol_vars <- findCorrelation(cor_matrix, cutoff = 0.65)
include_vars <- colnames(cor_matrix)[-multicol_vars]


# Baseline model ---------------------------------------------------------------
# initial regression model to serve as baseline
ind_vars <- paste0(include_vars, collapse = " + ")
formula <- as.formula(glue("avg_air_qual ~ {ind_vars}"))

# TODO: Check for collinearity among the independent variables in your model. You can use the vif function from the car package to inspect variance inflation factors. Removing or combining highly collinear variables might help. Additionally, ensure there's sufficient variability in your dependent variable and independent variables.

model1 <- lm(formula = formula, data = df)
summary(model1)

# Test for spatial autocorrelation ---------------------------------------------
# Get centroids
centroid_coords <- st_centroid(df)

# Create list of neighbors
neighbors_list <- knn2nb(knearneigh(centroid_coords, k = 100)) 

# Get distance for all spatial neighbor links
dists <- nbdists(neighbors_list, centroid_coords)

# Compute inverted distances
p <- 2
epsilon <- 0.0001
inverted_dists <- lapply(dists, function(x){1/(x^p + epsilon)})
#inverted_dists <- lapply(dists, function(x){1/(x)})

# # Normalize weights over their sum
# inverted_dists_normalized <- lapply(inverted_dists, function(weights) {
#   sum_weights = sum(weights)
#   weights / sum_weights
# })

# Get spatial weights for neighbours lists
wts <- nb2listw(neighbors_list, glist = inverted_dists, style = "B", zero.policy = FALSE) # inverse distance weights

# TODO: Consider adjusting the criteria for determining neighbors or the style of the weights. For example, if you're using a distance-based weight, decreasing the distance threshold might result in a less sparse matrix. If you're using a k-nearest neighbors approach, increasing k might help.
# TODO: Review the construction of your spatial weights matrix (wts). Ensure that it accurately represents the spatial relationships among observations. You might need to adjust the parameters when creating the matrix, such as using a different weighting scheme or including a row-standardization step if you haven't done so.

# use Morans I test if there is still autocorrelation in our residuals
moran.test(model1$residuals, wts)

residuals_model1 <- residuals(model1)
lagged_residuals_model1 <- lag.listw(wts, residuals_model1)

res <- data.frame("lagged_residuals" = lagged_residuals_model1, "residuals" = residuals_model1)

ggplot(res, aes(x = residuals, y = lagged_residuals)) +
  geom_point(alpha = 0.5) +
  geom_smooth(method = "lm", color = "red") +
  scale_x_continuous(labels = label_number(), breaks = pretty_breaks()) +
  scale_y_continuous(labels = label_number(), breaks = pretty_breaks()) +
  theme_void() 
#> The Moran’s I test statistic is strong and positive (0.72) and is statistically significant.

ggsave(here("figures/spatial-autocorrelation-los-angeles-air-quality.png"), height = 5, width = 5, dpi = 300)

# Spatial regression ===========================================================
## Spatially lagged X model ----------------------------------------------------
slx_model <- lmSLX(formula, data = df, listw = wts, zero.policy = TRUE)

summary(slx_model)

summary(impacts(slx_model))

# rerun Moran’s I to test if there is still autocorrelation in the residuals:
moran.test(slx_model$residuals, wts)
#> As Moran’s I still shows significant autocorrelation, we should assume that we have not yet captured the spatial dependence sufficiently with our model.

## Spatial lag model -----------------------------------------------------------
lag_model <- lagsarlm(
  formula = formula,
  data = df,
  listw = wts, # taking the same weights as before
  zero.policy = TRUE,
  tol.solve = 1e-10
)

summary(lag_model, Nagelkerke = TRUE)

imp <- impacts(lag_model, listw = wts, R = 100) # compute impacts
imp

#To print the p-values
summary(imp, zstats = TRUE)$pzmat

moran.test(lag_model$residuals, wts)

## Spatial error model ---------------------------------------------------------
error_model <- errorsarlm(
  formula = formula,
  data = df,
  listw = wts,
  zero.policy = TRUE
)
 
summary(error_model, Nagelkerke = TRUE)

moran.test(error_model$residuals, wts)

# Evaluate best model ==========================================================
lm.RStests(
  model1,
  wts,
  test = c("LMerr", "LMlag")
  # LM error, LM lag
)

#> If both resulting p-values are below the significance level (.05), this means we need to have a look at the robust version of these tests (Robust LM).
lm.RStests(
  model1,
  wts,
  test = c("RSerr", "RSlag")
  # robust RS error, robust RS lag
)

AIC(model1, 
    #lag_model, 
    error_model)
