# ==============================================================================
# Air (In)equality in Los Angeles
# 13 May 2024
# ==============================================================================


# Setup ------------------------------------------------------------------------
# Load dependencies
pacman::p_load(
  arrow,       # write files
  dplyr,       # wrangle data
  here,        # relative file paths
  janitor,     # tidy data
  readr,       # import data
  sf,          # simple features
  spatialreg,  # spatial regression
  spdep,       # spatial dependency
  stringr,     # character strings
  tidycensus,  # US census data
  tigris,      # spatial data
  units        # units
)

# Sign up for API key here: https://api.census.gov/data/key_signup.html

# Configure API key (if needed)
if (Sys.getenv("CENSUS_API_KEY") == "") { 
  census_api_key <- read_lines(here("api-keys/census-api-key.txt"))
  census_api_key(census_api_key, install = TRUE)
}

# Cache shapefiles for future use
options(tigris_use_cache = TRUE)


# Get US Census data -----------------------------------------------------------

# TODO: Update variables ...

# Define variables
# Variable info here: https://api.census.gov/data/2022/acs/acs1/spp/variables.html
vars <- c(
  total_population = "B01003_001E",
  white = "B02001_002E",
  black = "B02001_003E",
  native_american = "B02001_004E",
  asian = "B02001_005E",
  hi_pacific_islander = "B02001_006E",
  hispanic = "B03002_012E",
  poverty_status = "B17001_002E",
  median_house_income = "B19013_001E",
  income_per_cap = "B19301_001E",
  median_value = "B25077_001E",
  pct_college = "DP02_0068P"
)

# Load data
la_county <- get_acs(
  geography = "tract",
  variables = vars,
  year = 2022,
  state = "CA",
  county = "Los Angeles",
  geometry = TRUE,
  output = "wide"
  ) |> 
  clean_names() |> 
  select(-ends_with("m")) |> # drop margin of error
  rename_with(~str_remove(.x, "_e$")) |> # drop "_e" from end of variable names
  filter(!geoid %in% c("06037599000", "06037599100")) |> # remove islands (Catalina & San Clemente)
  relocate(geometry, .after = everything()) |> 
  st_as_sf() # convert from tibble to data.frame to avoid issues with the row names in the predictions

# Remove empty geometries
#la_county <- la_county[!st_is_empty(la_county$geometry), ]

# Save data
st_write(la_county, here("data/census/los-angeles-census-tracts.shp"), append = FALSE)

# Create bounding box
bbox <- la_county |> st_bbox() |> as.list() |> as.data.frame()
print(bbox)
write_feather(bbox, here("data/output/los-angeles-bbox.feather"))


# # Explore data -----------------------------------------------------------------
# qtm(la_county)
# mapview(la_county)
# la_county |> glimpse()
# la_county$geoid |> unique() |> length()
# la_county$name |> unique() |> length()
# la_county$geometry |> unique() |> length() # 2 duplicate geometries
# 
# plot(la_county["total_population"], lwd = 0.01)
# plot(la_county["pop_density"], lwd = 0.01)
# plot(la_county["pct_white"], lwd = 0.01)
#plot(la_county["poverty_status"], lwd = 0.01)
# 
# hist(la_county$total_population, nclass = 50)
# hist(la_county$white, nclass = 50)
# hist(la_county$income_per_cap, nclass = 50)
# hist(la_county$pct_college, nclass = 50)
# hist(la_county$pop_density, nclass = 50)
