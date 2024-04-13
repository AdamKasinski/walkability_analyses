using OpenStreetMapX
using OSMToolset
using Statistics
using Luxor
using SpatialIndexing



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