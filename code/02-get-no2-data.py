# ==============================================================================
# Air (In)equality in Los Angeles
# 13 May 2024
# ==============================================================================


# Load dependencies ------------------------------------------------------------
import pandas as pd

from sentinelhub import (
    SHConfig,
    CRS,
    BBox,
    DataCollection,
    MimeType,
    SentinelHubRequest
)

import os
os.environ["GTIFF_SRS_SOURCE"] = "EPSG"


# Configure API credentials -----------------------------------------------------
# Create an OAuth client at https://shapps.dataspace.copernicus.eu/dashboard/#/
# and export SH_CLIENT_ID and SH_CLIENT_SECRET before running this script.
sentinel_client_id = os.environ["SH_CLIENT_ID"]
sentinel_client_secret = os.environ["SH_CLIENT_SECRET"]


# Define key parameters --------------------------------------------------------
# Load bounding box area
bbox_df = pd.read_feather("data/output/los-angeles-bbox.feather")

# Extract bounding box coordinates
bbox_row = bbox_df.iloc[0] 
coordinates = [bbox_row['xmin'], bbox_row['ymin'], bbox_row['xmax'], bbox_row['ymax']]

# Create a BBox object
bbox = BBox(bbox=coordinates, crs=CRS.WGS84)

# Resolution in degrees
resolution_degrees = 0.005

# Bounding box coordinates in WGS 84
xmin, ymin, xmax, ymax = coordinates

# Calculate width and height in degrees
width_deg = xmax - xmin
height_deg = ymax - ymin

# Convert size from degrees to "pixels" (units at the given resolution)
width_px = int(width_deg / resolution_degrees)
height_px = int(height_deg / resolution_degrees)


# Configure Sentinel Hub Python profile ----------------------------------------
config = SHConfig()
config.sh_client_id = sentinel_client_id
config.sh_client_secret = sentinel_client_secret 
config.sh_base_url = "https://sh.dataspace.copernicus.eu"
config.sh_token_url = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"


# Download data ----------------------------------------------------------------
# Define eval script
evalscript_raw = """
//VERSION=3
function setup() {
  return {
    // This specifies the bands that are looked at
    // "dataMask" tells us whether or not there is data for a given tile
    input: ["NO2", "dataMask"],
    output: {
      bands: 1,
      sampleType: "FLOAT32" // data type to be returned
    },
    mosaicking: "ORBIT" // Will take all tiles over the specified period into account
    };
}

function isClear(sample) {
  return sample.dataMask == 1;
}

function sum(array) {
  let sum = 0;
  for (let i = 0; i < array.length; i++) {
    sum += array[i].NO2;
    }
  return sum;
}

function evaluatePixel(samples) {
  // Calculate mean of each pixel
  const clearTs = samples.filter(isClear)
  const mean = sum(clearTs) / clearTs.length
  return [mean]
}
"""

# Formulate API query
data_5p = DataCollection.SENTINEL5P.define_from("5p", service_url=config.sh_base_url)

request_raw = SentinelHubRequest(
    evalscript=evalscript_raw,
    input_data=[
        SentinelHubRequest.input_data(
            data_collection=data_5p,
            time_interval=("2023-07-01", "2023-07-31"),
        )
    ],
    responses=[SentinelHubRequest.output_response("default", MimeType.TIFF)],
    bbox=bbox,
    size=(width_px, height_px),
    config=config,
    data_folder="data/copernicus/",
)

# API request
raw_data = request_raw.get_data(save_data=True)
