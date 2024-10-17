using Luxor
using Plots
using IterTools
using DataFrames
using OpenStreetMapX
using SparseArrays

struct Edge
    from::Int
    to::Int
    from_LLA::LLA
    to_LLA::LLA
    way::Int
    type::String
end

function filter_ways(ways,road_types)
    filtered_ways = Vector{OpenStreetMapX.Way}()
    for way in ways
        if haskey(way.tags, "highway") && (way.tags["highway"] in road_types)
            push!(filtered_ways,way)
        end
    end
    return filtered_ways
end

function find_intersections(highways)
    seen = Set{Int}()
    intersections = Set{Int}()
    roads = Dict{Int,Vector{Int}}()
    roads_tags = Dict{Int,Dict{String,String}}()
    for highway in highways
        for i = 1:length(highway.nodes)
            if i == 1 || i == length(highway.nodes) || (highway.nodes[i] in seen)
                push!(intersections, highway.nodes[i])
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
    return roads, intersections, roads_tags
end

function ways_to_edges(ways,road_tags,parsed_map)
    edges = []
    for key in keys(ways)
        way = ways[key]
        for i in 1:length(way)-1
            if !haskey(road_tags[key],"oneway")
                edge = Edge(
                    way[i+1], #from    
                    way[i], #to
                    parsed_map.nodes[way[i+1]],#from_LLA
                    parsed_map.nodes[way[i]],#to_LLA
                    key,#way
                    road_tags[key]["highway"])# type
                push!(edges,edge)
            end
            edge = Edge(
                    way[i], #from
                    way[i+1],#to
                    parsed_map.nodes[way[i]],#from_LLA
                    parsed_map.nodes[way[i+1]],#to_LLA
                    key,  #way
                    road_tags[key]["highway"])# type
            push!(edges,edge)
        end
    end
    return edges
end

function edges_to_df(edges)
    df = DataFrame(
        id = [i for i in 1:length(edges)],
        from = [edge.from for edge in edges],
        to = [edge.to for edge in edges],
        from_LLA = [edge.from_LLA for edge in edges],         
        to_LLA = [edge.to_LLA for edge in edges],
        way = [edge.way for edge in edges],
        type = [edge.type for edge in edges]
    )
    return df
end

function get_sparsevec(df)
    edg = [(i,j) for (i,j) in zip(df.from,df.to)]
    return sparsevec(df.id,edg)
end