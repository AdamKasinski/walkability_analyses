using Luxor
using Colors
using Plots
using IterTools
using DataFrames
using OpenStreetMapX
using LightOSM
include("prepare_data.jl")
include("analyse.jl")
include("plots.jl")

city = "Kielce"
admin_level = "8"
search_area = 1000
attr = :police
wilderness_distance = 300
shape = "circle"
calculate_percent = true
num_of_points = 20
distance_sectors = 200.0
scrape_config = "poi_config_test.csv"
num_of_sectors = 100


points_prct,attr_prct,bounds_prct = calculate_attractiveness_for_city_sectors(                                      
                                     city, #city_name
                                     admin_level, #admin_level
                                     search_area, #search_area
                                     attr, #attr
                                     wilderness_distance, #wilderness_distance
                                     num_of_points, #num_of_points
#                                     distance_sectors=200,
                                     scrape_config = scrape_config)

attr_prct = min_max_scaling(attr_prct)


plot_attractiveness_of_sectors_abs(num_of_sectors,distance_sectors,
                            attr_prct,["Warsaw"])