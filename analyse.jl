using OpenStreetMapX
using OSMToolset
using Statistics
using Luxor
include("prepare_data.jl")
"""
generate n sectors inside the city

- 'distance'::Int - numer of sector to generate
- 'size_of_sector'::Int - radius of each sector
- 'centre'::LLA - centre of the map
- 'num_of_points'::Int - number of points to generate in each sector
- 'city_boundaries_lat'::Vector{Float64 - latitudes of the city boundaries
- 'city_boundaries_lon'::Vector{Float64} - longitudes of the city boundaries
"""

function generate_sectors(centre::LLA,num_of_points::Int,
    city_boundaries_lat::Vector{Float64},city_boundaries_lon::Vector{Float64},
                                                                    rectangle_bounds)
    min = ENU(LLA(rectangle_bounds["minlat"],rectangle_bounds["minlon"],0),centre)
    max = ENU(LLA(rectangle_bounds["maxlat"],rectangle_bounds["maxlon"],0),centre)
    dist_min = OpenStreetMapX.distance(min,ENU(0,0,0))
    dist_max = OpenStreetMapX.distance(max,ENU(0,0,0))
    distance = maximum([dist_min,dist_max])/100
    city_boundaries = Luxor.Point.(city_boundaries_lat,city_boundaries_lon)
    sectors = Array{ENU,2}(undef,100,num_of_points)
    for sector in 1:100
    sectors[sector,:] = generate_points_in_sector(distance*sector,centre,num_of_points,
                                                        city_boundaries)
    end
    return sectors
end


function generate_sectors(num_of_sectors::Int,distance::Float64,centre::LLA,num_of_points::Int,
                    city_boundaries_lat::Vector{Float64},city_boundaries_lon::Vector{Float64})
    
    city_boundaries = Luxor.Point.(city_boundaries_lat,city_boundaries_lon)
    sectors = Array{ENU,2}(undef,num_of_sectors,num_of_points)
    for sector in 1:num_of_sectors
        sectors[sector,:] = generate_points_in_sector(distance*sector,centre,num_of_points,
                                                                    city_boundaries)
    end
    return sectors
end

"""
generate n points around the center at a distance

- 'distance'::Int - distance at which points will be generated
- 'centre'::LLA - centre of the circle
- 'num_of_points'::Int - number of points to generate
- 'city_boundaries'::Vector{Luxor.Point} - boundaries of the city
"""
function generate_points_in_sector(distance::Float64,centre::LLA,num_of_points::Int,
                                                city_boundaries::Vector{Luxor.Point})
    radian::Float64 = 360/num_of_points*π/180
    points = [find_point_at_distance(distance, centre, point * radian, city_boundaries)
                                            for point in 1:num_of_points]
    return points
end


"""
generate a point at a distance n from the center

- 'radius'::Int - distance at which points will be generated
- 'centre'::LLA - centre of the circle
- 'radian'::Float64 - specifies the degree interval at which points should be generated 
- 'city_boundaries'::Vector{Luxor.Point} - boundaries of the city
"""
function find_point_at_distance(radius::Float64,centre::LLA, radian::Float64,city_boundaries)
    point = ENU(radius*cos(radian),radius*sin(radian),0)
    pt = Luxor.Point(point.east, point.north)
    if check_if_inside(city_boundaries,pt)
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
- 'points'::Array{LLA,2} - matrix with LLA points
- 'attractivenessSpatIndex'::attractivenessSpatIndex
- 'attribute'::Symbol - The category that will be used to calculate attractiveness
                        (:education, :entertainment, :healthcare, :leisure, :parking,
                        :restaurants, :shopping, :transport)
if generate_sectors function used, there is no need to use the function - attractiveness of
each point is already generated
"""
function calculate_attractiveness_of_points(points_matrix,attractivenessSpatIndex,
                                                                attribute::Symbol,centre)

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

"""
the function is currently being modified

determines the attractiveness of several cities based on specified attributes

- 'list_of_cities'::Vector{String} - list of cities
- 'num_of_sectors'::Int - number of sectors
- 'distance_for_sector'::Int - radius of each sector
- 'points_in_sector'::Int - number of points in each sector
- 'distance_to_analyse'::Int - search area radius
- 'csv'::Bool - a flag indicating whether POI should be taken from a CSV file or OSM
- 'center_dict'::Dict{String,LLA} - dictionary with centers of the cities
- 'list_of_attributes'::Vector{String} - vector of attributes based on which attractiveness will be determined
- 'city_boundaries::Dict{String,Vector{Luxor.Point}} - boundaries of the cities
"""


function calculate_attractiveness_for_city_points(city_name::String, admin_level::String, search_area::Int,
                                    num_of_sectors::Int,distance::Int,num_of_points::Int,attr)
    
    download_city_with_bounds(city_name,admin_level)

    if isfile("$city_name.csv")
        df_city = get_POI("$city_name.csv")
    else
        df_city = get_POI("$city_name.osm",nothing,"$city_name.csv")
    end

    download_boundaries_file("$city_name")
    boundaries_file = string(city_name,"_boundaries.osm")
    city_boundaries = extract_points_ENU(boundaries_file)

    city_centre = get_city_centre(boundaries_file)
    ix_city = AttractivenessSpatIndex(df_city,get_range=a->search_area)
    city_points = generate_sectors(num_of_sectors,distance,city_centre,num_of_points,
                                    city_boundaries.x,city_boundaries.y)

    return city_points, 
            calculate_attractiveness_of_points(city_points,ix_city,attr,city_centre),
            city_boundaries
end

function calculate_attractiveness_for_city_sectors(city_name::String, admin_level::String, search_area::Int,
    num_of_sectors::Int,distance::Int,num_of_points::Int,attr)

    download_city_with_bounds(city_name,admin_level)

    if isfile("$city_name.csv")
        df_city = get_POI("$city_name.csv")
    else
        df_city = get_POI("$city_name.osm",nothing,"$city_name.csv")
    end

    download_boundaries_file("$city_name")
    boundaries_file = string(city_name,"_boundaries.osm")
    city_boundaries = extract_points_ENU(boundaries_file)

    city_centre = get_city_cetre(boundaries_file)

    ix_city = AttractivenessSpatIndex(df_city,get_range=a->search_area)
    city_points = generate_sectors(num_of_sectors,distance,centre,num_of_points,
        city_boundaries.x,city_boundaries.y)

    attr_city = calculate_attractiveness_for_sector(city_points,ix_city,attr,city_centre)
    return min_max_scaling(attr_city)
end



"""
Determines whether a point lies within the city boundaries

- 'city_boundaries'::Vector{Luxor.Point} - boundaries of the city
- 'point'::Luxor.Point - the examined point
"""
function check_if_inside(city_boundaries::Vector{Luxor.Point}, point::Luxor.Point)
    return isinside(point,city_boundaries; allowonedge=true)
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