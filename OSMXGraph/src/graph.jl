module OSMXGraph

using Luxor
using Plots
using IterTools
using DataFrames
using OpenStreetMapX
using SparseArrays
using Distances
using NearestNeighbors
using CSV
using JSON

struct Edge
    id::Int
    from_id::Int
    to_id::Int
    from::Int
    to::Int
    from_LLA::LLA
    to_LLA::LLA
    way::Int
    type::String
end

export filter_ways, find_intersections, ways_to_edges, edges_to_df, create_sparse_index, create_road_index, find_nearest_point, save_file, read_file, create_road_graph, save_nodes, load_nodes, add_nearest_road_point

"""
    filter_ways(ways::Vector{Way}, road_types::Vector{String}) -> Vector{Way}

Filters a list of OpenStreetMapX 'Way' objects to include only those whose "highway" tag was included in road types vector.

# Arguments
- 'ways': A vector of 'Way' objects to filter.
- 'road_types': A vector of strings specifying the highway types to include.

# Returns
A vector of 'Way' objects that match the specified highway types.
"""

function filter_ways(ways::Vector{Way},road_types::Vector{String})
    filtered_ways = Vector{OpenStreetMapX.Way}()
    for way in ways
        if haskey(way.tags, "highway") && (way.tags["highway"] in road_types)
            push!(filtered_ways,way)
        end
    end
    return filtered_ways
end

"""
    find_intersections(highways::Vector{Way}, parsed_map::OpenStreetMapX.OSMData) -> (Dict{Int, Vector{Int}}, Set{Int}, Dict{Int, Dict{String, String}}, Dict{Int, Tuple{LLA, Int}})

Filters road vectors to beginnings, ends and intersections.

# Arguments
- 'highways': A vector of 'Way' objects representing highways.
- 'parsed_map': An 'OSMData' object containing parsed map data.

# Returns
A tuple containing:
- 'roads': A dictionary of roads mapped to their nodes.
- 'intersections': A set of node IDs that represent intersections.
- 'roads_tags': A dictionary of road tags for each highway.
- 'nds': A dictionary mapping node IDs to location data and index.
"""

function find_intersections(highways::Vector{Way},parsed_map::OpenStreetMapX.OSMData)
    seen = Set{Int}()
    intersections = Set{Int}()
    roads = Dict{Int,Vector{Int}}()
    roads_tags = Dict{Int,Dict{String,String}}()
    nds = Dict{Int,Tuple{LLA,Int}}()
    node_id = 1
    for highway in highways
        for i = 1:length(highway.nodes)
            if i == 1 || i == length(highway.nodes) || (highway.nodes[i] in seen)
                push!(intersections, highway.nodes[i])
                if !haskey(nds,highway.nodes[i])
                    nds[highway.nodes[i]] = (parsed_map.nodes[highway.nodes[i]],node_id)
                    node_id+=1
                end
            else
                push!(seen, highway.nodes[i])
            end
        end
        roads[highway.id] = Vector{Int}()
        roads_tags[highway.id] = highway.tags
    end
    for highway in highways
        for i = 1:length(highway.nodes)
            if i == 1 || i == length(highway.nodes) || highway.nodes[i] in intersections
                push!(roads[highway.id],(highway.nodes[i]))
            end
        end
    end
    return roads, intersections, roads_tags, nds
end

"""
    ways_to_edges(ways::Dict{Int64, Vector{Int64}}, road_tags::Dict{Int64, Dict{String, String}}, parsed_map::OpenStreetMapX.OSMData, nodes::Array{Int}) -> Vector{Edge}

Converts a dictionary of highways and node sequences into a vector of 'Edge' objects representing the graph's edges.

# Arguments
- 'ways': A dictionary mapping way IDs to node sequences.
- 'road_tags': A dictionary containing road tags for each way.
- 'parsed_map': An 'OSMData' object containing parsed map data.
- 'nodes': An array of node identifiers.

# Returns
A vector of 'Edge' objects representing bidirectional edges.
"""
function ways_to_edges(ways::Dict{Int64, Vector{Int64}},
                        road_tags::Dict{Int64, Dict{String, String}},
                        parsed_map::OpenStreetMapX.OSMData,
                        nodes::Dict{Int64, Tuple{LLA, Int64}})
    edges::Array{Edge} = []
    id=1
    for key in keys(ways)
        way = ways[key]
        for i in 1:length(way)-1
            if !haskey(road_tags[key],"oneway")
                push!(edges,Edge(
                        id,
                        nodes[way[i+1]][2],
                        nodes[way[i]][2],
                        way[i+1],   
                        way[i],
                        parsed_map.nodes[way[i+1]],
                        parsed_map.nodes[way[i]],
                        key,
                        road_tags[key]["highway"]))
                id+=1
            end
            push!(edges,Edge(
                    id,
                    nodes[way[i]][2],
                    nodes[way[i+1]][2],
                    way[i],
                    way[i+1],
                    parsed_map.nodes[way[i]],
                    parsed_map.nodes[way[i+1]],
                    key,
                    road_tags[key]["highway"]))
            id+=1
        end
    end
    return edges
end


"""
    edges_to_df(edges::Vector{Edge}) -> DataFrame

Converts a vector of 'Edge' objects into a 'DataFrame' with relevant edge information.

# Arguments
- 'edges': A vector of 'Edge' objects.

# Returns
A 'DataFrame' containing columns for each attribute of an edge, such as 'id', 'from_id', 'to_id', 'from', 'to', 'from_LLA', 'to_LLA', 'way', and 'type'.
"""
function edges_to_df(edges::Vector{Edge})
    df = DataFrame(
        id = [i for i in 1:length(edges)],
        from_id = [edge.from_id for edge in edges],
        to_id = [edge.to_id for edge in edges],
        from = [edge.from for edge in edges],
        to = [edge.to for edge in edges],
        from_LLA = [edge.from_LLA for edge in edges],         
        to_LLA = [edge.to_LLA for edge in edges],
        way = [edge.way for edge in edges],
        type = [edge.type for edge in edges]
    )
    return df
end

"""
    create_sparse_index(from::Vector{Int}, to::Vector{Int}, ids::Vector{Int}) -> SparseMatrixCSC

Creates a sparse adjacency matrix representing the connectivity between nodes.

# Arguments
- 'from': A vector of node IDs representing the starting points of edges.
- 'to': A vector of node IDs representing the endpoints of edges.
- 'ids': A vector of edge IDs corresponding to the 'from' and 'to' pairs.

# Returns
A 'SparseMatrixCSC' matrix representing node connections.
"""
function create_sparse_index(from::Vector{Int}, to::Vector{Int}, ids::Vector{Int})
    return sparse(from, to, ids)
end


"""
    create_road_index(points::Matrix{Float64}; leafsize=25, distance=Euclidean(), reorder=false) -> KDTree

Creates a spatial index for searching nearest points based on coordinates.

# Arguments
- 'points': A matrix of points, with each row representing a coordinate.
- 'leafsize': The number of points umber of points at which to stop splitting the tree.
- 'distance': The distance metric to use; defaults to Euclidean.
- 'reorder': Whether to reorder points; defaults to 'false'.

# Returns
A 'KDTree' object for nearest-neighbor queries.
"""
function create_road_index(points::Matrix{Float64};leafsize=25,
                                                distance=Euclidean(),reorder=false)
    return KDTree(points,distance;leafsize = leafsize, reorder = reorder)
end


"""
    find_nearest_point(tree, points_values::Vector{Int}, points_to_find::Union{Matrix{Float64}, Vector{Float64}}) -> Vector{Int}

Finds the nearest point in 'points_values' for each point in 'points_to_find' using a KDTree.

# Arguments
- 'tree': A 'KDTree' used for finding nearest points.
- 'points_values': A vector of point values to match.
- 'points_to_find': A matrix or vector of points to find the nearest neighbors for.

# Returns
A vector of indices corresponding to the nearest points in 'points_values'.
"""
function find_nearest_point(tree, points_values::Vector{Int}, 
                points_to_find::Union{Matrix{Float64},Vector{Float64}})
    indices::Vector{Int} = vcat(NearestNeighbors.knn(tree,points_to_find,1)[1]...)
    return points_values[indices] 
end

"""
    save_file(df::DataFrame, save_as::String; dir=".")

Saves a 'DataFrame' as a CSV file.

# Arguments
- 'df': The 'DataFrame' to save.
- 'save_as': The name to save the file as, including the file extension (".csv").
- 'dir': The directory in which to save the file. Defaults to the current directory (".").
"""
function save_file(df::DataFrame,save_as::String;dir=".")
    save_as=string(dir,"/",save_as)
    if save_as != ""
        CSV.write(save_as,df)
    end
end

"""
    read_file(file_name::String;dir::String=".")

Reads a .CSV file as a 'DataFrame'.

#Arguments
- 'file_name': Name of the file, including the file extension (".csv").
- 'dir':The directory in which to save the file. Defaults to the current directory (".").

#Returns
A DataFrame 
"""
function read_file(file_name::String;dir::String=".")
    file = string(dir,"/",file_name)
    return DataFrame(CSV.File(file))
end

"""
    create_road_graph(road_file::String, node_file::String; dir::String=".") -> (DataFrame, SparseMatrixCSC, KDTree, Vector{Int})

Loads road graph data from CSV and JSON files and constructs the graph and spatial index structures.

# Arguments

- `road_file`: The filename of the CSV file containing road edge data.
- `node_file`: The filename of the JSON file containing node data.
- `dir`: The directory where the files are located. Defaults to the current directory `"."`.

# Returns

A tuple containing:
- `df`: A `DataFrame` of edges loaded from `road_file`.
- `sparse_index`: A `SparseMatrixCSC` representing the adjacency matrix of the graph.
- `road_index`: A `KDTree` for spatial indexing of road nodes.
- `node_indices`: A vector of node indices.
"""
function create_road_graph(road_file::String,node_file::String;dir::String=".")
    df = OSMXGraph.read_file(string(dir,"/",road_file))
    sparse_index = OSMXGraph.create_sparse_index(df.from_id,df.to_id,df.id)
    nodes = load_nodes(string(dir,"/",node_file))
    lats = [node[1].lat for node in values(nodes)]
    lons = [node[1].lon for node in values(nodes)]
    node_indices = [node[2] for node in values(nodes)]
    road_mtrx = Matrix(transpose([lats lons]))
    road_index = OSMXGraph.create_road_index(road_mtrx)
    return df, sparse_index, road_index, node_indices
end

"""
    create_road_graph(osm_file::String, road_types::Vector{String}, graph_file_name::String, node_file_name::String; dir_in::String=".", dir_out::String=".") -> (DataFrame, SparseMatrixCSC, KDTree, Vector{Int})

Parses an OSM file to create a road graph and spatial index structures, saving the results to files.

# Arguments

- `osm_file`: The filename of the OpenStreetMap (`.osm`) file to parse.
- `road_types`: A vector of strings specifying the highway types to include.
- `graph_file_name`: The filename to save the edge `DataFrame` as (including `.csv`).
- `node_file_name`: The filename to save the node data as (including `.json`).
- `dir_in`: The directory where the OSM file is located. Defaults to the current directory `"."`.
- `dir_out`: The directory where the output files will be saved. Defaults to the current directory `"."`.

# Returns

A tuple containing:
- `df`: A `DataFrame` of edges.
- `sparse_index`: A `SparseMatrixCSC` representing the adjacency matrix of the graph.
- `road_index`: A `KDTree` for spatial indexing of road nodes.
- `vals`: A vector of node indices.

If the specified output files already exist, the function loads data from these files instead of parsing the OSM file.
"""
function create_road_graph(osm_file::String,road_types::Vector{String},
                            graph_file_name::String,node_file_name::String;dir_in::String=".",dir_out::String=".")
    
    if isfile(string(dir_out,"/",graph_file_name)) && isfile(string(dir_out,"/",node_file_name))
        return create_road_graph(graph_file_name,node_file_name,dir=dir_out)
    end
    parsed = OpenStreetMapX.parseOSM(string(dir_in,"/",osm_file))
    ways = parsed.ways
    filtered_ways = filter_ways(ways,road_types)
    ways_intersections, intersections, road_tags, nodes = OSMXGraph.find_intersections(filtered_ways, parsed)
    edges = OSMXGraph.ways_to_edges(ways_intersections,road_tags,parsed,nodes)
    df = OSMXGraph.edges_to_df(edges)
    save_file(df,string(dir_out,"/",graph_file_name))
    save_nodes(nodes,string(dir_out,"/",node_file_name))
    sparse_index = OSMXGraph.create_sparse_index(df.from_id,df.to_id,df.id)
    lats = [node[1].lat for node in values(nodes)]
    lons = [node[1].lon for node in values(nodes)]
    vals = [node[2] for node in values(nodes)]
    road_mtrx = Matrix(transpose([lats lons]))
    road_index = OSMXGraph.create_road_index(road_mtrx)
    return df, sparse_index, road_index, vals
end

"""
    save_nodes(nodes::Dict{Int, Tuple{LLA, Int}}, file_name::String)

Saves node data to a JSON file.

# Arguments

- `nodes`: A dictionary mapping node IDs to tuples containing `LLA` coordinates and an index.
- `file_name`: The filename to save the node data to.

The node data is saved in JSON format, where each key is a node ID (as a string), and each value is a tuple containing the latitude and longitude (as a tuple), and the index.
"""
function save_nodes(nodes::Dict{Int, Tuple{LLA, Int}}, file_name::String)
    dict_json = Dict(
        string(key) => [(value[1].lat, value[1].lon), value[2]] for 
                                                    (key, value) in nodes)
    open(file_name, "w") do f
        JSON.print(f, dict_json)
    end
end

"""
    load_nodes(file_name::String) -> Dict{Int, Tuple{LLA, Int}}

Loads node data from a JSON file.

# Arguments

- `file_name`: The filename of the JSON file containing node data.

# Returns

A dictionary mapping node IDs (as integers) to tuples containing `LLA` coordinates and an index.
"""
function load_nodes(file_name::String)
    node_json = JSON.parsefile(file_name)
    nodes = Dict(
        parse(Int, key) => (LLA(value[1][1], value[1][2], 0.0), value[2])
        for (key, value) in node_json
    )
    return nodes
end

"""
    add_nearest_road_point(POI_df::DataFrame, POI_xs::Vector{Float64}, POI_ys::Vector{Float64}, road_index::KDTree, road_nodes::Vector{Int}) -> DataFrame

Finds the nearest road node for each point of interest (POI) and adds it to the `DataFrame`.

# Arguments

- `POI_df`: A `DataFrame` containing the points of interest.
- `POI_xs`: A vector of x-coordinates (longitude) for the POIs.
- `POI_ys`: A vector of y-coordinates (latitude) for the POIs.
- `road_index`: A `KDTree` representing the spatial index of road nodes.
- `road_nodes`: A vector of node indices corresponding to the points in `road_index`.

# Returns

The updated `POI_df` `DataFrame` with a new column `nearest_road_node`, containing the index of the nearest road node for each POI.
"""
function add_nearest_road_point(POI_df::DataFrame,POI_xs::Vector{Float64},POI_ys::Vector{Float64},
                                road_index::KDTree,road_nodes::Vector{Int})
    POI_mtrx = Matrix(transpose([POI_xs POI_ys]))
    nearest_points = OSMXGraph.find_nearest_point(road_index,road_nodes,POI_mtrx)
    POI_df.nearest_road_node = nearest_points
    return POI_df
end

end