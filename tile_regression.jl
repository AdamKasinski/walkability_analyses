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

#    road_types = ["motorway", "trunk", "primary", "secondary", 
#                "tertiary", "residential", "service", "living_street", 
#                "motorway_link", "trunk_link", "primary_link", "secondary_link", 
#                "tertiary_link"]   


function calc_all_tiles_length(city_file,admin_level,city_centre,
                                road_types,ncols,nrows)

        parsed_map = OpenStreetMapX.parseOSM("$city_file.osm")
        tiles = generate_tiles(city,admin_level,ncols,nrows)
        tree = generate_index_ways(parsed_map,road_types,city_centre)
        tile_ways = put_ways_in_tiles(tree,tiles,city_centre)
        tls = collect(tile_ways)
        xs::Matrix{Float64} = zeros(Float64,ncols*nrows,4)
        ys::Matrix{Float64} = zeros(Float64,ncols*nrows,4)    
        tls_vals = []
        for (ind,tile) in enumerate(collect(tls))
            tl = tile[2]
            push!(tls_vals,calc_road_length(parsed_map,city_centre,tl))
            xs[ind,:] = tile[1][1]
            ys[ind,:] = tile[1][2]
        end
        return tls_vals, xs, ys
end

function put_ways_in_tiles(tree,tiles,city_centre)
    ways_in_tile = []
    for (ind, tile) in enumerate(tiles)
        min_point = ENU(LLA(tile.minlat,tile.minlon,0.0),city_centre)
        max_point = ENU(LLA(tile.maxlat,tile.maxlon,0.0),city_centre)
        points_in_tile = intersects_with(tree,SpatialIndexing.Rect((min_point.east,
                                                    min_point.north),
                                                    (max_point.east,
                                                    max_point.north)))
        x,y = rectangle(min_point.east,max_point.east,
            min_point.north,max_point.north)
        push!(ways_in_tile,[(x,y),points_in_tile])
    end
    return ways_in_tile
end


function calc_road_length(city_parse, city_centre, tile_data)
    tile_parse = Dict()
    for tile in tile_data
        if haskey(tile_parse,tile.val[1])
            push!(tile_parse[tile.val[1]],tile.val[2])
        else
            tile_parse[tile.val[1]] = [tile.val[2]]
        end
    end
    tile_parse = filter(((k,v),) -> length(v) > 1, tile_parse)
    
    total_length = 0.0 
    for (key, val) in tile_parse
        index = findfirst(w -> w.id == key, city_parse.ways)
        way_nodes = city_parse.ways[index].nodes[sort(val)]
        nodes = [ENU(city_parse.nodes[nd], city_centre) for nd in way_nodes]
        for node_ind in 1:(length(nodes)-1)
            total_length += OpenStreetMapX.distance(nodes[node_ind],
                                                    nodes[node_ind+1])
        end
    end
    return total_length
end

function calc_tile_road_length(city_parse_data,city_centre,road_types)

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

function rectangle(min_east,max_east,min_north,max_north)
    return [min_east,max_east, max_east, min_east],
    [min_north,min_north,max_north, max_north]
        
            
end

function rectangle(bounds, centre)
    ENU_coords = ENU(bounds,centre)

    return [ENU_coords.min_x, ENU_coords.max_x,
            ENU_coords.max_x, ENU_coords.min_x], 
            [ENU_coords.min_y, ENU_coords.min_y,
            ENU_coords.max_y, ENU_coords.max_y]
end

function get_city_bounds(city_name)
    boundaries_file = string(city_name,"_boundaries.osm")
    admin_city_centre = get_city_centre(boundaries_file)
    city_boundaries = extract_points_ENU(boundaries_file,admin_city_centre)
    return city_boundaries, admin_city_centre
end

function extract_tiles(city::String, nrows::Int, ncols::Int, out_dir)
    if isdir(out_dir)
        rm(out_dir,recursive=true)
        mkdir(out_dir)
    else
        mkdir(out_dir)
    end
    
    tile_osm_file(string(city,".osm"), nrow=nrows,ncol=ncols,
                                                out_dir=out_dir)

end

function split_map(city, admin_level)
    bnds = get_city_bounds(city,admin_level)
    minlat = bnds["minlat"]
    minlon = bnds["minlon"]
    maxlat = bnds["maxlat"]
    maxlon = bnds["maxlon"]
    return OSMToolset.Bounds(;minlat, minlon, maxlat, maxlon)
end

function get_tile_values_from_files(city::String, nrows, ncols, tiles_path,
                                    road_types)

    num_of_tiles::Int = nrows*ncols
    files = readdir(tiles_path)
    bounds = Vector{Union{OpenStreetMapX.Bounds{LLA}, Nothing}}(undef, 
                                                            num_of_tiles)
    lengths::Array{Float64} = zeros(Float64,num_of_tiles)
    areas::Array{Float64} = zeros(Float64,num_of_tiles)
    xs::Matrix{Float64} = zeros(Float64,num_of_tiles,4)
    ys::Matrix{Float64} = zeros(Float64,num_of_tiles,4)

    boundaries, admin_city_centre = get_city_bounds(city)
    for (i, elem) in enumerate(files)
        file = joinpath(tiles_path,elem)
        city_parse = OpenStreetMapX.parseOSM(file)
        city_map = create_map(file; use_cache = false, trim_to_connected_graph=false)
        city_centre = OpenStreetMapX.center(city_map.bounds)
        bounds[i] = city_map.bounds
        lengths[i] = calc_tile_road_length(city_parse,city_centre,road_types)
        areas[i] = calc_tile_area(city_map.bounds,city_centre)
        x,y = rectangle(city_map.bounds,admin_city_centre)
        xs[i,:] = x
        ys[i,:] = y    
    end
    density::Array{Float64} = min_max_scaling(lengths./areas)
    return boundaries, density, xs, ys
end


function agregate_values_in_tiles(loc_points::Matrix{Union{Nothing, ENU}},
                                values::Matrix{Float64},
                                tiles::Matrix{OSMToolset.Bounds},
                                city_centre::LLA)
    tree = generate_index_val(loc_points,values)
    xs::Matrix{Float64} = zeros(Float64,length(tiles),4)
    ys::Matrix{Float64} = zeros(Float64,length(tiles),4)
    vals = []
    for (ind, tile) in enumerate(tiles)
        min_point = ENU(LLA(tile.minlat,tile.minlon,0.0),city_centre)
        max_point = ENU(LLA(tile.maxlat,tile.maxlon,0.0),city_centre)
        points_in_tile = intersects_with(tree,SpatialIndexing.Rect((min_point.east,
                                                    min_point.north),
                                                    (max_point.east,
                                                    max_point.north)))
        vls = collect(points_in_tile)
        x,y = rectangle(min_point.east,max_point.east,
                        min_point.north,max_point.north)
        xs[ind,:] = x
        ys[ind,:] = y
        push!(vals, sum([v.val for v in vls])/length(vls))
    end
    return xs,ys,vals
end

function generate_tiles(city::String,admin_level::String,nrows::Int,ncols::Int)
    bnds::OSMToolset.Bounds = split_map(city,admin_level)
    tiles::Matrix{OSMToolset.Bounds} = reshape(
        OSMToolset.BoundsTiles(;bounds=bnds,nrow=nrows,ncol=ncols).tiles,(nrows*ncols,1))
    return tiles
end