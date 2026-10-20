# SMARTIRRIGATE RWANDA — TEAM NIYOISHIMWE
# R workflow: download Rwanda district boundaries (geodata::gadm), read
# Earth Engine Drive exports after you copy them to Documents/Hackathon/GEE_Exports,
# validate, and export analysis-ready files into YOUR working directory.
# This DOES NOT change the original files.

packages <- c('sf','terra','geodata','readr','dplyr','purrr','stringr','tidyr')
missing_pkgs <- packages[!vapply(packages,requireNamespace,logical(1),quietly=TRUE)]
if(length(missing_pkgs)) install.packages(missing_pkgs)
invisible(lapply(packages,library,character.only=TRUE))

# Set this line to your own folder if needed, e.g. C:/Users/NAME/Documents/Hackathon
hackathon_dir <- file.path(path.expand('~'),'Documents','Hackathon')
if(!dir.exists(hackathon_dir)) stop('Set hackathon_dir to your existing Documents/Hackathon folder.')
setwd(hackathon_dir)
cat('Working directory:',getwd(),'\n')

# Copy CSVs/GeoTIFFs from Google Drive SmartIrrigate_GEE_2000_2026 into this folder.
gee_dir <- file.path(getwd(),'GEE_Exports')
dir.create(gee_dir,recursive=TRUE,showWarnings=FALSE)
out_dir <- file.path(getwd(),'Additional_Data','Prepared_Soil_Atmosphere')
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
cache_dir <- file.path(getwd(),'Additional_Data','GADM_cache')
dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)

# Official GADM is different from NISR and FAO GAUL. Do not join by numeric code;
# harmonize district names and verify the polygons before any spatial comparison.
rwa <- geodata::gadm(country='RWA',level=2,path=cache_dir)
rwa_sf <- sf::st_as_sf(rwa)
sf::st_write(rwa_sf,file.path(out_dir,'rwanda_gadm_districts.gpkg'),delete_dsn=TRUE,quiet=TRUE)
cat('GADM polygons:',nrow(rwa_sf),'\n')

# 1. Read 2000–2026 atmosphere CSVs from GEE, combine into one data table.
atmos_files <- list.files(gee_dir,pattern='^atmos_rwanda_district_month_20[0-9]{2}\\.csv$',
                          full.names=TRUE,recursive=TRUE)
if(length(atmos_files)){
  atmosphere <- purrr::map_dfr(atmos_files, ~readr::read_csv(.x,show_col_types=FALSE)) %>%
    dplyr::filter(year>=2000,year<=2026) %>%
    dplyr::mutate(year=as.integer(year),month=as.integer(month)) %>%
    dplyr::arrange(district,year,month)
  if(anyDuplicated(atmosphere[c('district','year','month')]))
    warning('Duplicate district-year-months: inspect before analysis.')
  readr::write_csv(atmosphere,file.path(out_dir,'rwanda_atmosphere_district_month_2000_2026.csv'))
  saveRDS(atmosphere,file.path(out_dir,'rwanda_atmosphere_district_month_2000_2026.rds'))
  # Do not fill future or missing 2026 months with zeros.
  counts <- atmosphere %>% count(year,name='district_month_rows')
  readr::write_csv(counts,file.path(out_dir,'atmosphere_year_coverage.csv'))
  cat('Atmosphere data rows:',nrow(atmosphere),'\n')
} else message('No atmosphere CSV found yet. Complete GEE Tasks and copy files into GEE_Exports.')

# 2. Read district soil table (all depths, continuous properties).
soil_csv <- list.files(gee_dir,pattern='^soil_district_means\\.csv$',
                       full.names=TRUE,recursive=TRUE)
if(length(soil_csv)){
 soil <- readr::read_csv(soil_csv[1],show_col_types=FALSE)
 readr::write_csv(soil,file.path(out_dir,'rwanda_soil_district_all_depths.csv'))
 saveRDS(soil,file.path(out_dir,'rwanda_soil_district_all_depths.rds'))
 cat('Soil district observations:',nrow(soil),'\n')
} else message('No district soil CSV yet. Run the soil export task in GEE.')

# 3. Preserve raster maps at their source spatial resolution for future suitability modelling.
soil_tifs <- list.files(gee_dir,pattern='^soil_.*\\.tif(f)?$',full.names=TRUE,recursive=TRUE)
if(length(soil_tifs)){
 tif_out <- file.path(out_dir,'soil_rasters')
 dir.create(tif_out,recursive=TRUE,showWarnings=FALSE)
 for(f in soil_tifs){
  raster <- terra::rast(f)
  terra::writeRaster(raster,file.path(tif_out,basename(f)),overwrite=TRUE)
 }
 message(length(soil_tifs),' soil raster(s) preserved.')
}

# 4. Optional: download independent historical climatology in R (NOT annual 2000–2026).
# Uncomment only if needed; downloads can be large:
# wc <- geodata::worldclim_country(country='RWA',var='tavg',res=2.5,path=cache_dir)
# terra::writeRaster(wc,file.path(out_dir,'worldclim_monthly_temperature_normals.tif'),overwrite=TRUE)

# Data dictionary of the prepared atmosphere columns (reference; not a data recode).
dictionary <- tibble::tribble(
 ~variable,~unit,~meaning,
 'temperature_c','deg C','ERA5-Land monthly mean 2m air temperature',
 'dewpoint_c','deg C','Monthly mean dew point',
 'relative_humidity_pct_approx','%','Approximate RH from monthly mean temperature and dew point',
 'wind_speed_m_s','m/s','Magnitude of monthly mean wind vector, not mean instantaneous speed',
 'surface_pressure_kpa','kPa','Monthly mean surface pressure',
 'soil_water_m3m3_l1','m3/m3','ERA5-Land top soil water volumetric fraction',
 'soil_water_m3m3_l2','m3/m3','ERA5-Land second soil layer water fraction',
 'soil_water_m3m3_l3','m3/m3','ERA5-Land third soil layer water fraction',
 'soil_water_m3m3_l4','m3/m3','ERA5-Land fourth soil layer water fraction',
 'era5_precip_mm','mm/month','ERA5 model precipitation; prefer CHIRPS for rainfall study',
 'solar_radiation_mj_m2','MJ/m2/month','Monthly incoming shortwave energy total',
 'potential_evaporation_mm_era5','mm/month','ERA5 potential evaporation, NOT FAO reference ET0',
 'actual_evaporation_mm_era5','mm/month','ERA5 net evaporation sign-inverted',
 'runoff_mm','mm/month','ERA5 modelled runoff',
 'clay_pct_d0','%','Modelled static clay at 0 cm (other depths d10,d30,d60,d100,d200)',
 'sand_pct_d0','%','Modelled static sand at 0 cm',
 'ph_h2o_d0','pH','Static modelled soil pH at 0 cm',
 'organic_carbon_g_kg_d0','g/kg','Modelled organic carbon 0 cm',
 'bulk_density_kg_m3_d0','kg/m3','Modelled bulk density 0 cm',
 'field_capacity_pct_d0','%','Modelled field capacity 0 cm'
)
readr::write_csv(dictionary,file.path(out_dir,'soil_atmosphere_data_dictionary.csv'))
cat('Outputs saved to:',out_dir,'\n')
