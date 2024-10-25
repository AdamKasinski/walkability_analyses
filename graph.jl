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

function filter_ways(ways::Vector{Way},road_types::Vector{String})
    filtered_ways = Vector{OpenStreetMapX.Way}()
    for way in ways
        if haskey(way.tags, "highway") && (way.tags["highway"] in road_types)
            push!(filtered_ways,way)
        end
    end
    return filtered_ways
end

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
                #push!(edges,edge)
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
            #push!(edges,edge)
            id+=1
        end
    end
    resize!(edges,edge_index-1)
    return edges
end

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

function create_sparse_index(from::Vector{Int}, to::Vector{Int}, ids::Vector{Int})
    return sparse(from, to, ids)
end

function create_road_index(points::Matrix{Float64};leafsize=25,
                                                distance=Euclidean(),reorder=false)
    return KDTree(points,distance;leafsize = leafsize, reorder = reorder)
end

function find_nearest_point(tree, points_values::Vector{Int}, 
    points_to_find::Union{Matrix{Float64},Vector{Float64}})

    indices::Vector{Int} = vcat(NearestNeighbors.knn(tree,points_to_find,1)[1]...)
    return points_values[indices] 
end