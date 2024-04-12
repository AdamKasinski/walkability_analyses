using OpenStreetMapX
using OSMToolset
using Statistics
using Luxor
using SpatialIndexing
include("prepare_data.jl")

"""
The function generates 100 sectors evenly spaced apart

- 'centre'::LLA - centre of the map
- 'num_of_points'::Int - number of points to generate in each sector
- 'city_boundaries_north'::Vector{Float64 - latitudes of the city boundaries
- 'city_boundaries_east'::Vector{Float64} - longitudes of the city boundaries
- 'rectangle_bounds'::Dict{String, Any} - the furthest points of the city
"""
function generate_sectors(centre::LLA,
                        num_of_points::Int,
                        city_boundaries_east::Vector{Float64},
                        city_boundaries_north::Vector{Float64},
                        rectangle_bounds, 
                        tree)

    min = ENU(LLA(rectangle_bounds["minlat"],rectangle_bounds["minlon"],0),centre)
    max = ENU(LLA(rectangle_bounds["maxlat"],rectangle_bounds["maxlon"],0),centre)
    dist_min = OpenStreetMapX.distance(min,ENU(0,0,0))
    dist_max = OpenStreetMapX.distance(max,ENU(0,0,0))
    distance = maximum([dist_min,dist_max])/100
    city_boundaries = Luxor.Point.(city_boundaries_east,city_boundaries_north)
    sectors = Array{ENU,2}(undef,100,num_of_points)
    for sector in 1:100
    sectors[sector,:] = generate_points_in_sector(distance*sector,num_of_points,
                                                        city_boundaries,tree)
    end
    return sectors
end

"""
The function generate n sectors inside the city

- 'distance'::Int - numer of sector to generate
- 'size_of_sector'::Int - radius of each sector
- 'centre'::LLA - centre of the map
- 'num_of_points'::Int - number of points to generate in each sector
- 'city_boundaries_north'::Vector{Float64 - latitudes of the city boundaries
- 'city_boundaries_east'::Vector{Float64} - longitudes of the city boundaries
"""
function generate_sectors(num_of_sectors::Int,distance::Float64,num_of_points::Int,
                        city_boundaries_east::Vector{Float64},
                        city_boundaries_north::Vector{Float64},tree)
    
    city_boundaries = Luxor.Point.(city_boundaries_east,city_boundaries_north)
    sectors = Array{ENU,2}(undef,num_of_sectors,num_of_points)
    for sector in 1:num_of_sectors
        sectors[sector,:] = generate_points_in_sector(distance*sector,num_of_points,
                                                                city_boundaries,tree)
    end
    return sectors
end

"""
The function generates n points around the center at a distance

- 'distance'::Int - distance at which points will be generated
- 'centre'::LLA - centre of the circle
- 'num_of_points'::Int - number of points to generate
- 'city_boundaries'::Vector{Luxor.Point} - boundaries of the city
"""
function generate_points_in_sector(distance::Float64,num_of_points::Int,
                                            city_boundaries::Vector{Luxor.Point},tree)
    radian::Float64 = 360/num_of_points*π/180
    points = [find_point_at_distance(distance, point * radian, city_boundaries,tree)
                                            for point in 1:num_of_points]
    return points
end


function check_point(point, city_boundaries, tree)

    pt = Luxor.Point(point.east, point.north)

    if check_if_inside(city_boundaries,pt) && check_if_in_wilderness(tree,point)
        return point
    end
    return ENU(Inf16,Inf16,Inf16)
end

function generate_rectangles(centre, boundaries_east, boundaries_north, rectangle_bounds,distance, tree)

    min = ENU(LLA(rectangle_bounds["minlat"],rectangle_bounds["minlon"],0),centre)
    max = ENU(LLA(rectangle_bounds["maxlat"],rectangle_bounds["maxlon"],0),centre)
    city_boundaries = Luxor.Point.(boundaries_east,boundaries_north)
    x_distance = max.east - min.east
    y_distance = max.north - min.north
    
    num_of_x = ceil(Int,x_distance/distance)
    num_of_y = ceil(Int,y_distance/distance)

    x_cords = range(min.east, stop=max.east, length=num_of_x)
    y_cords = range(min.north, stop=max.north, length=num_of_y)
    city_cords = Matrix{Union{ENU,Nothing}}(nothing,num_of_x,num_of_y)

    for (x_ind, x) in enumerate(x_cords)
        for (y_ind, y) in enumerate(y_cords)
            point = ENU(x,y,0.0)
            city_cords[x_ind,y_ind] = check_point(point,city_boundaries, tree)
        end
    end
    return city_cords
end
"""
The function generates a point at a distance n from the center

- 'radius'::Int - distance at which points will be generated
- 'centre'::LLA - centre of the circle
- 'radian'::Float64 - specifies the degree interval at which points should be generated 
- 'city_boundaries'::Vector{Luxor.Point} - boundaries of the city
"""

function find_point_at_distance(radius::Float64, radian::Float64,city_boundaries,
                                                                            tree)
    point = ENU(radius*cos(radian),radius*sin(radian),0)
    pt = Luxor.Point(point.east, point.north)

    if check_if_inside(city_boundaries,pt) && check_if_in_wilderness(tree,point)
        return point
    end
    return ENU(Inf16,Inf16,Inf16)
end

"""
- 'points'::Array{LLA,2} - matrix with LLA points
- 'attractivenessSpatIndex'::attractivenessSpatIndex
- 'attribute'::Symbol - The category that will be used to calculate attractiveness
                        (:education, :entertainment, :healthcare, :leisure, :parking,
                        :restaurants, :shopping, :transport)
if generate_sectors function used, there is no need to use the function - attractiveness of
each point is already generated
"""
function calculate_attractiveness_of_sector(points_matrix,attractivenessSpatIndex,
                                                                attribute::Symbol,centre::LLA)

    dim1, dim2 = size(points_matrix)
    attract = Array{Float64}(undef, dim1)
    attrs = [Float64[] for _ in 1:Threads.nthreads()]
    Threads.@threads for i in 1:dim1
        attr = attrs[Threads.threadid()]
        fill!(attr, 0.0)
        for j in 1:dim2
            if points_matrix[i,j] != ENU(Inf16,Inf16,Inf16)
                pt = LLA(points_matrix[i,j],centre)
                push!(attr,getfield(OSMToolset.attractiveness(
                    attractivenessSpatIndex,pt),attribute))
            end
        end
        attract[i] = mean(attr)
    end
    return attract
end

"""
The function calculates attractiveness of points

- 'points'::Array{LLA,2} - matrix with LLA points
- 'attractivenessSpatIndex'::attractivenessSpatIndex
- 'attribute'::Symbol - The category that will be used to calculate attractiveness
                        (:education, :entertainment, :healthcare, :leisure, :parking,
                        :restaurants, :shopping, :transport)
if generate_sectors function used, there is no need to use the function - attractiveness of
each point is already generated
"""
function calculate_attractiveness_of_points(points_matrix,attractivenessSpatIndex,
                                            attribute::Symbol,centre::LLA)

    dim1, dim2 = size(points_matrix)
    attr_matrix = zeros(Float64,dim1,dim2)
    for i in 1:dim1
        for j in 1:dim2
            if points_matrix[i,j] != ENU(Inf16,Inf16,Inf16)
                pt = LLA(points_matrix[i,j],centre)
                attr_matrix[i,j] = getfield(OSMToolset.attractiveness(
                    attractivenessSpatIndex,pt),attribute)
            end
        end
    end
    return attr_matrix
end


"""
The function transforms a vector using min_max

- 'vec'::Vector{Float64} - vector which should be transformed
"""
function min_max_scaling(vec::Vector{Float64})
    mins = minimum(vec)
    maxs = maximum(vec)
    (vec.-mins)/(maxs-mins)
end

function min_max_scaling(mat::Matrix{Float64})
    mins = minimum(mat)
    maxs = maximum(mat)
    (mat .- mins) ./ (maxs - mins)
end

"""
The function generates points within a city boundaries and calculates attractiveness of 
each point. If num_of_sectors and distance parameters have default values, the functions 
generates 100 sectors evenly spaced apart.

- 'city_name'::String - name of the city
- 'admin_level'::String - level at which city will be analysed
- 'search_area'::Int - the radius of the area in which objects will be searched
- 'num_of_points'::Int - number of points in each sector
- 'attr'::Symbol - The category that will be used to calculate attractiveness
                    (:education, :entertainment, :healthcare, :leisure, :parking,
                    :restaurants, :shopping, :transport)
- 'num_of_sectors' - number of sectors
- 'distance' - distance between sectors
"""

function calculate_attractiveness_for_city_points(city_name::String, admin_level::String, 
                                                search_area::Int,num_of_points::Int,
                                                attr::Symbol,wilderness_distance,shape,
                                                dist,
                                                num_of_sectors=0, distance=0.0)
    
    download_city_with_bounds(city_name,admin_level)

    if isfile("$city_name.csv")
        df_city = get_POI("$city_name.csv")
    else
        df_city = get_POI("$city_name.osm",nothing,"$city_name.csv")
    end

    download_boundaries_file(city_name,admin_level)
    boundaries_file = string(city_name,"_boundaries.osm")
    city_map = create_map("$city_name.osm")
    city_centre = OpenStreetMapX.center(city_map.bounds)
    city_boundaries = extract_points_ENU(boundaries_file,city_centre)
    admin_city_centre = get_city_centre(boundaries_file)
    ix_city = AttractivenessSpatIndex(df_city,get_range=a->search_area)
    rectangle_boundaries = get_city_bounds(city_name,admin_level)
    city_tree = generate_index(wilderness_distance, city_map.nodes)
    if shape == "circle"
        if num_of_sectors == 0
            city_points = generate_sectors(city_centre,num_of_points,city_boundaries.x,
                                city_boundaries.y,rectangle_boundaries,city_tree)

        else

            city_points = generate_sectors(num_of_sectors,distance,
                                            num_of_points,city_boundaries.x,
                                            city_boundaries.y,city_tree)

        end
    elseif shape == "rectangle"
        city_points = generate_rectangles(city_centre,city_boundaries.x,city_boundaries.y,
                                            rectangle_boundaries,dist,city_tree)
    end

    return city_points,
            to_zero.(
                    log.(calculate_attractiveness_of_points(city_points,
                                                ix_city,attr,city_centre)
            )),
            city_boundaries
end

function to_zero(elem)
    if elem == Inf || elem < 0 
        return 0
    end
    return elem
end


"""
The function generates points within a city boundaries and calculates average attractiveness 
for each sector. If num_of_sectors and distance parameters have default values, the functions 
generates 100 sectors evenly spaced apart

- 'city_name'::String - name of the city
- 'admin_level'::String - level at which city will be analysed
- 'search_area'::Int - the radius of the area in which objects will be searched
- 'num_of_points'::Int - number of points in each sector
- 'attr'::Symbol - The category that will be used to calculate attractiveness
                    (:education, :entertainment, :healthcare, :leisure, :parking,
                    :restaurants, :shopping, :transport)
- 'num_of_sectors' - number of sectors
- 'distance' - distance between sectors
"""

function calculate_attractiveness_for_city_sectors(city_name::String, admin_level::String, 
                                                    search_area::Int,num_of_points::Int,
                                                    attr::Symbol,wilderness_distance,
                                                    num_of_sectors=nothing, distance=nothing)

    download_city_with_bounds(city_name,admin_level)

    if isfile("$city_name.csv")
        df_city = get_POI("$city_name.csv")
    else
        df_city = get_POI("$city_name.osm",nothing,"$city_name.csv")
    end

    download_boundaries_file(city_name,admin_level)
    boundaries_file = string(city_name,"_boundaries.osm")
    city_map = create_map("$city_name.osm")
    city_centre = OpenStreetMapX.center(city_map.bounds)
    city_boundaries = extract_points_ENU(boundaries_file,city_centre)

    #admin_city_centre = get_city_centre(boundaries_file)
    ix_city = AttractivenessSpatIndex(df_city,get_range=a->search_area)

    city_tree = generate_index(wilderness_distance, city_map.nodes)
    if num_of_sectors === nothing

        rectangle_boundaries = get_city_bounds(city_name,admin_level)
        city_points = generate_sectors(city_centre,num_of_points,city_boundaries.x,
        city_boundaries.y,rectangle_boundaries,city_tree)

    else

        city_points = generate_sectors(num_of_sectors,distance,city_centre,num_of_points,
        city_boundaries.x,city_boundaries.y)

    end

    return city_points, 
        min_max_scaling(calculate_attractiveness_of_sector(
            city_points,ix_city,attr,city_centre)),
        
        city_boundaries
end



#function isinside(point::Point, pointlist::Array{Point,1}, epsilon::Float64;
#                  allowonedge::Bool = false)::Bool
#    xs = [point.x for point in boundaries]
#    ys = [point.y for point in boundaries]
#    epsilon = 5
#    filtered_xs = ys[findall(x -> x > point.x, xs)]
#    filtered_ys = findall(y -> (y < point.y+epsilon)
#                            && (y > point.y-epsilon),filtered_xs)
#    return 
#end

"""
The function determines whether a point lies within the city boundaries

- 'city_boundaries'::Vector{Luxor.Point} - boundaries of the city
- 'point'::Luxor.Point - the examined point
"""
function check_if_inside(city_boundaries::Vector{Luxor.Point}, point::Luxor.Point)
    return Luxor.isinside(point,city_boundaries; allowonedge=false)
end

function ENU_matrix_to_LLA_matrix(ENU_matrix,centre_point::LLA)
    dim1, dim2 = size(ENU_matrix)
    LLA_matrix = [LLA(0.0,0.0,0.0) for _ in 1:dim1, _ in 1:dim2]
    for i in 1:dim1
        for j in 1:dim2
            fill!(LLA_matrix,LLA(ENU_matrix[i,j],centre_point))
        end
    end
    return LLA_matrix
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

