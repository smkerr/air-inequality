# ==============================================================================
# Air (In)equality in Los Angeles
# 13 May 2024
# ==============================================================================


# Setup ------------------------------------------------------------------------
# Load packages
pacman::p_load(
  dplyr,        # wrangle data
  ggspatial,    # spatial plots               
  glue,         # expressive strings          
  here,         # file paths          
  readr,        # import data           
  sf,           # simple features        
  stringr,      # character strings             
  terra         # raster data           
)

# Load pollution data
air_qual <- rast(here("data/copernicus/response.tiff"))
names(air_qual) <- "avg_air_qual" # rename layer

# Load US census data 
la_county <- st_read(here("data/census/los-angeles-census-tracts.shp"))


# Combine data -----------------------------------------------------------------
# Align vector data CRS with raster data CRS
la_county <- st_transform(la_county, crs = st_crs(air_qual))

# Calculate average air quality (NO2 column density, mol/m2) by neighborhood
avg_air_qual <- extract(air_qual, la_county, fun = mean, na.rm = TRUE) 

# Append average air quality to vector data
la_county$avg_air_qual <- avg_air_qual$avg_air_qual

# Save merged data
st_write(la_county, here("data/output/los-angeles-air-quality.shp"), append = FALSE, delete_dsn = TRUE, delete_layer = TRUE)
