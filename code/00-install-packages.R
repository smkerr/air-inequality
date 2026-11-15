# Install every R package used in this project
pkgs <- c(
  "pacman", "arrow", "caret", "cowplot", "dplyr", "ggplot2", "ggspatial",
  "glue", "here", "janitor", "kableExtra", "knitr", "mapview", "patchwork",
  "purrr", "readr", "reticulate", "scales", "sf", "spatialreg", "spdep",
  "stringr", "terra", "tidycensus", "tigris", "tmap", "units"
)
install.packages(setdiff(pkgs, rownames(installed.packages())))
