using Luxor
using Colors
using Plots
using IterTools
using DataFrames
using OpenStreetMapX
using LightOSM
using KernelDensity
using Parsers
using Downloads
using OSMToolset
include("kernel_density.jl")
include("distance.jl")
include("prepare_data.jl")
include("analyse.jl")
include("plots.jl")
include("transform.jl")
include("tile_regression.jl")
include("kernel_density.jl")


scrape_config = "poi_config_test.csv"
scr = OSMToolset.ScrapePOIConfig(DataFrame(CSV.File(scrape_config)))
DATA_PATH = "data"
city = "Kielce"
admin_level = "8"
search_area = 1000
attr = :education
wilderness_distance = 300
shape = "rectangle"
calculate_percent = true
num_of_points = 30
distance_sectors = 200.0
scrape_config = "poi_config_test.csv"
num_of_sectors = 100
ncols=10
nrows=10

data = prepare_city_map(city, #city_name
            admin_level, #admin_level
            search_area, #search_area
            wilderness_distance, #wilderness_distance
            shape, #shap;
            distance_sectors=300,
            rectangle_boundaries= get_city_bounds(city,admin_level),
            #calculate_percent = calculate_percent,
            #num_of_points = num_of_points,
            scrape_config = scrape_config,
            in_admin_bounds=false,dir=DATA_PATH)

city_centre = data[2]


road_types = ["motorway", "trunk", "primary", "secondary", 
                "tertiary", "residential", "service", "living_street",
                "motorway_link", "trunk_link", "primary_link", "secondary_link", 
                "tertiary_link"]    


tiles = generate_tiles("Kielce","8",nrows,ncols,dir=DATA_PATH)

tls,xs,ys = calc_all_tiles_length(city,city_centre,road_types,tiles,
                                        nrows,ncols,dir=DATA_PATH)

center_in_tile(tiles,city_centre)

tile_plot(data[5],tls,xs,ys,"sad")