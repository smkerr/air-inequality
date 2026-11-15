# ==============================================================================
# Air (In)equality in Los Angeles
# 13 May 2024
# ==============================================================================


# Setup ------------------------------------------------------------------------
# Load dependencies
pacman::p_load(
  dplyr,       # wrangle data
  ggplot2,     # plots
  here,        # file paths
  mapview,     # interactive maps
  scales,      # plot scales
  sf,          # simple features
  terra,       # raster data
  tmap         # thematic maps
)

# Load pollution data
air_qual <- rast(here("data/copernicus/response.tiff")) # 1 month
air_qual_week <- rast(here("data/copernicus/response-week.tiff")) # 1 week
air_qual_day <- rast(here("data/copernicus/response-day.tiff")) # 1 day

# Rename layers
names(air_qual) <- "avg_air_qual" 
names(air_qual_week) <- "avg_air_qual"  
names(air_qual_day) <- "avg_air_qual"  

# Load US census data 
la_county <- st_read(here("data/census/los-angeles-census-tracts.shp"))

# Load merged data
df <- st_read(here("data/output/los-angeles-air-quality.shp")) |> 
  na.omit() |> # remove observations with missing data
  rename( # restore variable names
    "total_pop" =  "ttl_ppl", ###  
    "income_per_cap" = "incm_p_" ,
    "pct_college" = "pct_cll",
    "pop_density" = "pp_dnst",
    #"pct_white" = "pct_wht",
    "avg_air_qual" = "avg_r_q"
  )


# Visualize data ---------------------------------------------------------------
# Distribution of NO2 levels
ggplot(df, aes(x = avg_air_qual)) + 
  geom_histogram(binwidth = .00001, fill = "#10477E", color = "black") +
  scale_x_continuous(labels = label_number(), expand = expansion(), breaks = pretty_breaks()) +
  scale_y_continuous(expand = expansion(), breaks = pretty_breaks()) +
  labs(
    #title = "Distribution of average NO2 amongst census tracts",
    #subtitle = "Los Angeles, Jan 2023",
    x = NULL, #"NO2 ppm",
    y = NULL #"Count"
  ) +
  theme_classic() 

ggsave(here("figures/histogram-los-angeles-air-quality.png"), height = 5, width = 7.5, dpi = 300)


# Map of vector data superimposed over raster data (from 1 day)
rast_df <- as.data.frame(air_qual_day, xy = TRUE)
vect_df <- la_county |> st_boundary()
p1 <- ggplot() +
  geom_raster(data = rast_df, aes(x = x, y = y, fill = avg_air_qual)) + 
  geom_sf(data = vect_df, lwd = 0.25) +
  scale_fill_gradient2(
    low = "#91bfdb",
    mid = "#ffffbf",
    high = "#fc8d59",
    na.value = "lightgrey",
    midpoint = median(df$avg_air_qual, na.rm = TRUE),
    labels = label_number()
  ) +
  labs(
    #title = "Los Angeles's Air Quality",
    #subtitle = expression("Average "*NO[2]*" levels in July 2023"),
    x = NULL,
    y = NULL,
    fill = NULL, #expression(NO[2]*" ppm"), 
    caption = NULL #"sources: Copernicus Sentinel Hub, US Census Bureau"
  ) +
  theme_void() + 
  theme(
    legend.position = "none",
    axis.text.x = element_blank(), #element_text(angle = 45, vjust = 0.5, hjust = 0.5),
    axis.text.y = element_blank()  #element_text()
  )
ggsave(here("figures/map-los-angeles-air-quality-tiles-day.png"))


# Map of vector data superimposed over raster data (from 1 week)
rast_df <- as.data.frame(air_qual_week, xy = TRUE)
vect_df <- la_county |> st_boundary()
p2 <- ggplot() +
  geom_raster(data = rast_df, aes(x = x, y = y, fill = avg_air_qual)) + 
  geom_sf(data = vect_df, lwd = 0.25) +
  scale_fill_gradient2(
    low = "#91bfdb",
    mid = "#ffffbf",
    high = "#fc8d59",
    na.value = "lightgrey",
    midpoint = median(df$avg_air_qual, na.rm = TRUE),
    labels = label_number()
  ) +
  labs(
    #title = "Los Angeles's Air Quality",
    #subtitle = expression("Average "*NO[2]*" levels in July 2023"),
    x = NULL,
    y = NULL,
    fill = NULL, #expression(NO[2]*" ppm"), 
    caption = NULL #"sources: Copernicus Sentinel Hub, US Census Bureau"
  ) +
  theme_void() + 
  theme(
    legend.position = "none",
    axis.text.x = element_blank(), #element_text(angle = 45, vjust = 0.5, hjust = 0.5),
    axis.text.y = element_blank()
  )

ggsave(here("figures/map-los-angeles-air-quality-tiles-week.png"))


###
tm_shape(df) + tm_polygons(fill = "avg_air_qual") + tm_basemap(server = providers$Esri.WorldImagery)

# Map of vector data superimposed over raster data
rast_df <- as.data.frame(air_qual, xy = TRUE)
vect_df <- la_county |> st_boundary()
p3 <- ggplot() +
  geom_raster(data = rast_df, aes(x = x, y = y, fill = avg_air_qual)) + 
  geom_sf(data = vect_df, lwd = 0.25) +
  scale_fill_gradient2(
    low = "#91bfdb",
    mid = "#ffffbf",
    high = "#fc8d59",
    na.value = "lightgrey",
    midpoint = median(df$avg_air_qual, na.rm = TRUE),
    labels = label_number()
  ) +
  labs(
    #title = "Los Angeles's Air Quality",
    #subtitle = expression("Average "*NO[2]*" levels in July 2023"),
    x = NULL,
    y = NULL,
    fill = NULL, # expression(NO[2]*" ppm"), 
    caption = NULL #"sources: Copernicus Sentinel Hub, US Census Bureau"
  ) +
  theme_void() + 
  theme(
    legend.position = "none",
    axis.text.x = element_blank(), #element_text(angle = 45, vjust = 0.5, hjust = 0.5),
    axis.text.y = element_blank() #element_text()
    )

ggsave(here("figures/map-los-angeles-air-quality-tiles.png"))


# Map of average air quality by census tract 
p4 <- la_county |> 
  st_transform(crs(air_qual)) |> 
  st_join(df) |> 
  ggplot() +
  geom_sf(aes(fill = avg_air_qual), lwd = 0.25) +
  scale_fill_gradient2(
    low = "#91bfdb",
    mid = "#ffffbf",
    high = "#fc8d59",
    na.value = "lightgrey",
    midpoint = median(df$avg_air_qual, na.rm = TRUE),
    labels = label_number()
  ) +
  labs(
    title = NULL, # "Los Angeles's Air Quality",
    subtitle = NULL, # expression("Average "*NO[2]*" levels in July 2023"),
    x = NULL,
    y = NULL,
    fill = expression(NO[2]*" ppm"), 
    caption = NULL #"sources: Copernicus Sentinel Hub, US Census Bureau"
  ) +
  theme_void() + 
  theme(
    axis.text.x = element_text(angle = 45, vjust = 0.5, hjust = 0.5),
    axis.text.y = element_text()
  )

ggsave(here("figures/map-los-angeles-air-quality-areal.png"))

# Combine maps into single plot
library(cowplot)
top_row <- plot_grid(
  p1, p2, p3, 
  nrow = 1,
  align = "v",
  rel_widths = c(1, 1, 1)
  )
final_plot <- plot_grid(
  top_row, 
  p4, 
  ncol = 1, 
  rel_heights = c(1, 3),
  rel_widths = c(1)
)

# Add title, subtitle, and caption
title <- draw_label("Los Angeles's Air Quality", fontface = 'bold', size = 22)
subtitle <- draw_label("Average NO2 levels in July 2023", size = 15)
caption <- draw_label("Sources: Copernicus Sentinel Hub, US Census Bureau", size = 12)

# Combine the title, subtitle, the plots, and the caption
final_plot_with_labels <- plot_grid(
  title, 
  subtitle,
  final_plot,
  caption, 
  ncol = 1, 
  rel_heights = c(0.1, 0.05, 5, 0.1)  # Adjust these values as needed
)

print(final_plot_with_labels)

ggsave(
  here("figures/map-los-angeles-air-quality.png"), 
  final_plot_with_labels, 
  width = 10, height = 8, dpi = 300
  )

###
library(patchwork)
(p1 | p2 | p3) /
  p4 +
  plot_layout(heights = c(1, 3)) +
  plot_annotation(
    title = 'Los Angeles\'s Air Quality',
    subtitle = 'Average NO2 levels in July 2023',
    caption = 'Sources: Copernicus Sentinel Hub, US Census Bureau'
  )

### 
library(gridExtra)
grid.arrange(
  grobs = list(top_row, p4),
  ncol = 1,
  heights = c(1, 3)
)

###
library(ggpubr)
ggarrange(
  p1, p2, p3,
  p4,
  ncol = 1, nrow = 2,
  #labels = c("A", "B", "C", "D"),
  heights = c(1, 3)
)
