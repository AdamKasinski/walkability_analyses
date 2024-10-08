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

function main(city,level,attrs;search_area=1000,ncols=20,nrows=20,clean=true)
    city = city
    admin_level = level
    search_area = search_area
#    attrs = [:universities,:education, :entertainment, :healthcare, :leisure, :parking,
#                        :restaurants, :shopping, :transport]
    wilderness_distance = 300
    shape = "rectangle"
    calculate_percent = true
    num_of_points = 30
    distance_sectors = 200.0
    #scrape_config = "poi_config_test.csv"
    ncols=ncols
    nrows=nrows
    num_of_sectors = ncols*nrows

    road_types = ["motorway", "trunk", "primary", "secondary", 
                "tertiary", "residential", "service", "living_street",
                "motorway_link", "trunk_link", "primary_link", "secondary_link", 
                "tertiary_link"]
    
    scp_config = "poi_config_test.csv"

    data = prepare_city_map(city, #city_name
            admin_level, #admin_level
            search_area, #search_area
            wilderness_distance, #wilderness_distance
            shape, #shap;
            distance_sectors = distance_sectors,
            rectangle_boundaries= get_city_bounds(city,admin_level),
            #calculate_percent = calculate_percent,
            #num_of_points = num_of_points,
            scrape_config = scp_config,
            in_admin_bounds=false)

    city_centre = data[2]
    tiles = generate_tiles(city,admin_level,ncols,nrows)
    tls,xs,ys = calc_all_tiles_length(city,city_centre,road_types,tiles,ncols,nrows)

    lengths_plot = tile_plot(data[5],tls,xs,ys,string(city," ", "road_length"))
    if clean
        savefig(lengths_plot,string("plots_tile_20/",city,"_length.svg"))
    end
    dim1, dim2 = size(xs)
    LLA_matrix = [LLA(0.0,0.0,0.0) for _ in 1:dim1, _ in 1:dim2]
    for i in 1:dim1
        for j in 1:dim2
            LLA_matrix[i,j] = LLA(ENU(xs[i,j],ys[i,j],0.0),city_centre)
        end
    end

    south_lat = []
    north_lat = []
    west_lng = []
    east_lng = []

    for pol in 1:dim1
        push!(south_lat, minimum([i.lat for i in LLA_matrix[pol,:]]))
        push!(north_lat, maximum([i.lat for i in LLA_matrix[pol,:]]))
        push!(west_lng, minimum([i.lon for i in LLA_matrix[pol,:]]))
        push!(east_lng, maximum([i.lon for i in LLA_matrix[pol,:]]))
    end

    LLA_coords = DataFrame(
        south_lat = south_lat,
        north_lat = north_lat,
        west_lng = west_lng,
        east_lng = east_lng    
    )
    if clean
        CSV.write(string("spatial_data_20/",city,"_LLA_coords.csv"),LLA_coords)
    end

    for attr in attrs
        points_heat,attr_heat,bounds_heat = calculate_attractiveness_for_city_points(data, attr)
        attr_heat = matrix_log_scaling(attr_heat)

        attr_xs,attr_ys, tile_attrs = agregate_values_in_tiles(points_heat,attr_heat,tiles,city_centre)
        vls = DataFrame(lengths = tls,
                        attr = tile_attrs)
        attrs_plot = tile_plot(data[5], tile_attrs, attr_xs, attr_ys,string(city," ",attr))
        if clean
            savefig(attrs_plot,string("plots_tile_20/",city,"_",attr,"attr.svg"))
            CSV.write(string("spatial_data_20/",city,"_",attr,"_attr_length.csv"),vls)
        end    
    end
end

main("Kraków","6",[:education, :healthcare, 
                    :leisure, :parking])

#main("Warszawa","6",[:universities],search_area=50,ncols=2,nrows=2,clean=false)