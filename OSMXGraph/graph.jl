module OSMXGraph

using Luxor
using Plots
using IterTools
using DataFrames
using OpenStreetMapX
using SparseArrays

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

export filter_ways, find_intersections, ways_to_edges, edges_to_df, create_sparse_index, create_road_index, find_nearest_point
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
                        parsed_map::OpenStreetMapX.OSMData,nodes::Array{Int})
    edges = Vector{Edge}(undef,(length(way)-1)*2)
    id=1
    for key in keys(ways)
        way = ways[key]
        for i in 1:length(way)-1
            if !haskey(road_tags[key],"oneway")
                edges[id] = Edge(
                        id,
                        nodes[way[i+1]][2],
                        nodes[way[i]][2],
                        way[i+1],   
                        way[i],
                        parsed_map.nodes[way[i+1]],
                        parsed_map.nodes[way[i]],
                        key,
                        road_tags[key]["highway"])
                id+=1
            end
            edges[id] = Edge(
                    id,
                    nodes[way[i]][2],
                    nodes[way[i+1]][2],
                    way[i],
                    way[i+1],
                    parsed_map.nodes[way[i]],
                    parsed_map.nodes[way[i+1]],
                    key,
                    road_tags[key]["highway"])
            id+=1
        end
    end
    resize!(edges,edge_index-1)
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

end