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

function calc_tile_road_length(city_parse_data,city_centre)
    road_types = ["motorway", "trunk", "primary", "secondary", 
                "tertiary", "residential", "service", "living_street", 
                "motorway_link", "trunk_link", "primary_link", "secondary_link", 
                "tertiary_link"]
    
    total_length = 0.0
    
    for way in city_parse_data.ways
        if haskey(way.tags, "highway") && (way.tags["highway"] in road_types)
            for i in 1:(length(way.nodes) - 1)
                node1 = ENU(city_parse_data.nodes[way.nodes[i]],city_centre)
                node2 = ENU(city_parse_data.nodes[way.nodes[i + 1]],city_centre)
                total_length += OpenStreetMapX.distance(node1,node2)
            end
        end
    end
    return total_length
end

function calc_tile_area(bounds,tile_centre)
    node1 = ENU(bounds,tile_centre)
    return node1.min_x*2*node1.min_y*2
end

"""
y - lat/east
x - lon/north
"""
function rectangle(bounds, centre)
    ENU_coords = ENU(bounds,centre)

    return [ENU_coords.min_y, ENU_coords.min_y,
            ENU_coords.max_y, ENU_coords.max_y],
            [ENU_coords.min_x, ENU_coords.max_x,
            ENU_coords.max_x, ENU_coords.min_x]
end

function get_city_bounds(city_name)
    boundaries_file = string(city_name,"_boundaries.osm")
    admin_city_centre = get_city_centre(boundaries_file)
    city_boundaries = extract_points_ENU(boundaries_file,admin_city_centre)
    return city_boundaries, admin_city_centre
end

