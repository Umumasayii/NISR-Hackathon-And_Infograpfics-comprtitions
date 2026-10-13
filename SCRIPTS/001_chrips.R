rm(list = ls())
chrips <- read.csv("CHIRPS/CHRIPS District-Month 1981-2025 data.csv")
library(dplyr)
library(ggplot2)
library(plotly)
library(tidyverse)
library(stringr)

library(sf)


rwanda <- sf::st_read("GADM/gadm41_RWA_2.shp")

rwanda <- rwanda %>% 
  select(NAME_1, NAME_2, geometry) %>% 
  rename(province = NAME_1, district = NAME_2)

crips_v <- chrips %>% 
  group_by(district) %>% 
  summarise(rainfall = mean(rainfall_total_mm, na.rm = T))
## merging rwanda with crips_v
unique(rwanda$province)

rwa_rain <- left_join(crips_v, rwanda, by = "district")

rw_rain <- sf::st_as_sf(rwa_rain)

# ggplot(data = rw_rain) +
#   geom_sf(aes(fill = rainfall), color = "white", linewidth = 0.2) +
#   scale_fill_gradient(low = "lightblue", high = "darkblue", na.value = "grey80") +
#   theme_void() + # Removes the background grid and axes
#   labs(
#     title = "Total Rainfall by District in Rwanda",
#     fill = "Rainfall (mm)"
#   )

data <- chrips

View(data)

data <- data %>% 
  mutate(day = round(runif(n = nrow(data), min = 1, max = 28))) %>% 
  mutate(
    day = as.factor(day),
    month = as.factor(month),
    year = as.factor(year)
    )

# View(data)
library(tidyr)

?as.Date
data <- data %>% 
  unite("Date",c(year, month, day), sep = "/",remove = F) %>% 
  mutate(Date = as.Date(Date, origin = "1899-12-30"))

p_data <- data %>% 
  select(Date, rainfall_total_mm) %>% 
  rename(ds = Date, y = rainfall_total_mm)
head(p_data)

library(prophet)

model <- prophet(p_data)

future = make_future_dataframe(m = model,freq = "d",periods = 24)

forecast <- predict(model, future)
yearly_forec <- forecast %>%
  select(ds, yhat_lower, yhat, yhat_upper) %>% 
  group_by(year(ds)) %>% 
  summarise(mean_rain = mean(yhat))
# esquisse::esquisser(yearly_forec)

library(ggplot2)

ggplot(yearly_forec) +
 aes(x = `year(ds)`, y = mean_rain) +
 geom_point(colour = "#112446") +
 geom_line(linewidth = 1.5, 
 colour = "#114644") +
 labs(x = "Year", y = "Average Rainfall", title = "Rainfall Predictions (1981-2027)", 
 subtitle = "Source: Google Earth Engine (Brancha Lee)") +
 ggthemes::theme_base() +
 theme(plot.title = element_text(size = 15L, 
 face = "bold", hjust = 0.5), plot.subtitle = element_text(size = 12L, face = "bold.italic", hjust = 0.5), 
 axis.title.y = element_text(size = 12L, face = "bold"), axis.title.x = element_text(size = 12L, face = "bold"), 
 axis.text.x = element_text(face = "bold", size = 11L), legend.text = element_text(face = "bold", 
 size = 11L), legend.title = element_text(face = "bold", size = 11L))











