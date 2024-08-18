using OpenStreetMapX
using OSMToolset
using Statistics
using Luxor
using SpatialIndexing


function generate_index_ways(parsed_map, road_types,city_centre) 
    ways = parsed_map.ways
    data = SpatialElem{Float64, 2, Int64, Tuple{Int,Int}}[]
    id = 1
    for way in ways
        if haskey(way.tags, "highway") && (way.tags["highway"] in road_types)
            for point in 1:(length(way.nodes))
                node = ENU(parsed_map.nodes[way.nodes[point]],city_centre)
                rect = SpatialIndexing.Rect((node.east,node.north),
                                            (node.east,node.north))
                push!(data,SpatialElem(rect,id,(way.id,point)))
            end
            id+=1
        end
    end
    tree = RTree{Float64,2}(Int, Tuple{Int,Int}, variant=SpatialIndexing.RTreeStar)
    SpatialIndexing.load!(tree,data)
end


function generate_index_val(nodes, values) 
    
    data = SpatialElem{Float64, 2, Int64, Float64}[]
    id = 1

    for i in 1:size(nodes,1)
        for j in 1:size(nodes,2)
            node = nodes[i,j]
            value = values[i,j]
            rect = SpatialIndexing.Rect((node.east,node.north),
                                        (node.east,node.north))
            push!(data,SpatialElem(rect,id,value))
            id+=1
        end
    end
    tree = RTree{Float64,2}(Int, Float64, variant=SpatialIndexing.RTreeStar)
    SpatialIndexing.load!(tree,data)
end


function generate_index(node_range, map_nodes)

    ET = Pair{Int64, Tuple{Float64, Float64}}
    data = SpatialElem{Float64, 2, Int64, ET }[]
    id = 0

    for (node, enu) in map_nodes
        east = enu.east
        north = enu.north
        rect = SpatialIndexing.Rect((east-node_range, north-node_range),
                                    (east+node_range, north+node_range))
        push!(data, SpatialElem(rect, id, node=>(east, north)))
        id+=1
    end
    tree = RTree{Float64, 2}(Int, ET, variant=SpatialIndexing.RTreeStar)
    SpatialIndexing.load!(tree, data)
    
end


function findnode(tree::RTree, enu::ENU)
    p = SpatialIndexing.Point((enu.east, enu.north))
    ee = intersects_with(tree, SpatialIndexing.Rect(p))
    return collect(ee)
end


function check_if_in_wilderness(tree::RTree, enu::ENU)
    if length(findnode(tree, enu)) != 0
        return true
    end
    return false 
end


"""
The function determines whether a point lies within the city boundaries

- 'city_boundaries'::Vector{Luxor.Point} - boundaries of the city
- 'point'::Luxor.Point - the examined point
"""
function check_if_inside(city_boundaries::Vector{Luxor.Point}, point::Luxor.Point)
    return Luxor.isinside(point,city_boundaries; allowonedge=false)
end