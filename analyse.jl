using OpenStreetMapX
using OSMToolset
using Statistics
using Luxor
using SpatialIndexing
using Match
include("prepare_data.jl")
include("sectors.jl")
include("transform.jl")
include("point_search.jl")

# TODO
# 1) get the generate sectors function right - rectangle, circle - add more function 
# 2) check type of points - it is better to keep one type for check_if_inside
# 3) create function which prepare all necessary data - boundaries, poi etc.
# 4) change the POI file - e.g. university
# 5) try to add KNN method instead average calculation 

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
                                            attribute::Symbol,centre::LLA;
                                            calculate_attractiveness::Function=OSMToolset.calculate_attractiveness, 
                                            distance::Function=OpenStreetMapX.distance)

    dim1, dim2 = size(points_matrix)
    attr_matrix = zeros(Float64,dim1,dim2)
    #attr = getfield(attribute)
    for i in 1:dim1
        for j in 1:dim2
            if points_matrix[i,j] != ENU(Inf16,Inf16,Inf16)
                pt = LLA(points_matrix[i,j],centre)
                attr_matrix[i,j] = getfield(OSMToolset.attractiveness(
                    attractivenessSpatIndex,pt,
                    calculate_attractiveness=calculate_attractiveness, 
                    distance=distance),attribute)
            end
        end
    end
    return attr_matrix
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

function actual_route_distance(m::MapData, routing::Symbol,center, enu1::ENU, enu2::ENU)
    point1 = LLA(enu1,center)#(enu1.east,enu1.north)
    point2 = LLA(enu2,center)#(enu2.east,enu2.north)
    node1 = point_to_nodes(point1,m)
    node2 = point_to_nodes(point2,m)
    # Call the shortest_route function with the appropriate MapData and nodes
    route_nodes, distance, route_time = OpenStreetMapX.shortest_route(m, node1, node2, routing=routing)
    return distance  # Return only the distance value
end

function calculate_attractiveness_for_city_points(city_name::String, 
                        admin_level::String, search_area::Int,attr::Symbol,
                        wilderness_distance,shape;calculate_percent=false,
                        distance_sectors=0.0,num_of_points=0.0,num_of_sectors=0.0,
                        scrape_config = nothing,
                        calculate_attractiveness::Function=OSMToolset.calculate_attractiveness, 
                        distance::Function=OpenStreetMapX.distance)
    
    download_city_with_bounds(city_name,admin_level)

    if isfile("$city_name.csv")
        df_city = get_POI("$city_name.csv",scrape_config)
    else
        df_city = get_POI("$city_name.osm",scrape_config,"$city_name.csv")
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
    min_point = ENU(LLA(rectangle_boundaries["minlat"],
                        rectangle_boundaries["minlon"],0),city_centre)
    max_point = ENU(LLA(rectangle_boundaries["maxlat"],
                        rectangle_boundaries["maxlon"],0),city_centre)

    if calculate_percent
        dist_min = OpenStreetMapX.distance(min_point,ENU(0,0,0))
        dist_max = OpenStreetMapX.distance(max_point,ENU(0,0,0))
        distance_sectors = maximum([dist_min,dist_max])/100
        num_of_sectors = 100
    end

    shape_arguments = get_shape_args(shape, city_boundaries, 
                                    city_tree,distance_sectors, num_of_points, 
                                    num_of_sectors,rectangle_boundaries,
                                    min_point, max_point)

    if shape == "circle"
        points = generate_sectors(shape_arguments...)
    elseif shape == "rectangle"
        points = generate_rectangles(shape_arguments...)
    end

    actual_route_distance_arg = (enu1, enu2) -> actual_route_distance(city_map,
                            :astar,city_centre, enu1, enu2)
    return points,
            calculate_attractiveness_of_points(points,
                                ix_city,attr,city_centre,
                    calculate_attractiveness = calculate_attractiveness, 
                    distance= distance),
            city_boundaries
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
                                                search_area::Int,attr::Symbol,
                                                wilderness_distance,num_of_points;
                                                calculate_percent=false, distance=0.0,num_of_sectors=0.0)

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
    rectangle_boundaries = get_city_bounds(city_name,admin_level)
    city_tree = generate_index(wilderness_distance, city_map.nodes)

    if calculate_percent
        min_point = ENU(LLA(rectangle_boundaries["minlat"],
                        rectangle_boundaries["minlon"],0),city_centre)
        max_point = ENU(LLA(rectangle_boundaries["maxlat"],
                        rectangle_boundaries["maxlon"],0),city_centre)
        dist_min = OpenStreetMapX.distance(min_point,ENU(0,0,0))
        dist_max = OpenStreetMapX.distance(max_point,ENU(0,0,0))
        distance = maximum([dist_min,dist_max])/100
        num_of_sectors = 100
    end

    shape_arguments = get_shape_args("circle", city_boundaries, 
                                    city_tree,distance, num_of_points, 
                                    num_of_sectors,rectangle_boundaries,
                                    min_point, max_point)


    points = generate_sectors(shape_arguments...)

    return points, 
        calculate_attractiveness_of_sector(
            points,ix_city,attr,city_centre),
        city_boundaries
end


