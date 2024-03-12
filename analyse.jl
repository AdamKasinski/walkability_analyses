using OpenStreetMapX
using OSMToolset
using Statistics
using Luxor

# TODO jest balagan z kolejnoscia importow bo jupyter notebook tez importuje prepare_data.jl
# W kodzie trzeba miec porzadek bo inaczej ciezko goutrzymac i aktualizwoac
# Rysunki w Plots i folium?

"""
generate n sectors inside the city

- 'distance'::Int - numer of sector to generate
- 'size_of_sector'::Int - radius of each sector
- 'centre'::LLA - centre of the map
- 'num_of_points'::Int - number of points to generate in each sector
- 'city_boundaries_lat'::Vector{Float64 - latitudes of the city boundaries
- 'city_boundaries_lon'::Vector{Float64} - longitudes of the city boundaries
"""
function generate_sectors(num_of_sectors::Int,distance::Int,centre::LLA,num_of_points::Int,
                    city_boundaries_lat::Vector{Float64},city_boundaries_lon::Vector{Float64})
    city_boundaries = Luxor.Point.(city_boundaries_lat,city_boundaries_lon)
    sectors = Array{LLA,2}(undef,num_of_sectors,num_of_points)
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
function generate_points_in_sector(distance::Int,centre::LLA,num_of_points::Int,
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
function find_point_at_distance(radius::Int,centre::LLA, radian::Float64,city_boundaries)
    point = LLA(ENU(radius*cos(radian),radius*sin(radian),0),centre)
    pt = Luxor.Point(point.lat, point.lon)
    if check_if_inside(city_boundaries,pt)
        return point
    end
    return LLA(0.0,0.0,0.0)
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
                                                                attribute::Symbol)

    dim1, dim2 = size(points_matrix)
    attract = Array{Float64}(undef, dim1)
    attrs = [Float64[] for _ in 1:Threads.nthreads()]
    Threads.@threads for i in 1:dim1
        attr = attrs[Threads.threadid()]
        fill!(attr, 0.0)
        for j in 1:dim2
            if points_matrix[i,j] != LLA(0,0,0)
                push!(attr,getfield(OSMToolset.attractiveness(
                    attractivenessSpatIndex,points_matrix[i,j]),attribute))
            end
        end
        attract[i] = mean(attr)
    end
    return attract
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

function comparison(list_of_cities::Vector{String},num_of_sectors::Int,distance_for_sector::Int,
                                points_in_sector::Int, distance_to_analyse::Int,csv::Bool, 
                                center_dict::Dict{String,LLA},list_of_attributes::Vector{String},
                                city_boundaries::Dict{String,Vector{Luxor.Point}})

    dfs = []
    centers = []
    ixs = []
    points = []

    attr_of_cities = Dict(city => Dict(attribute => fill(0.0, num_of_sectors) for
                                attribute in list_of_attributes) for city in list_of_cities)

    for city in list_of_cities
        download_data(city)
    end

    for (index, city) in enumerate(list_of_cities)

        if csv
            ct = get_POI(string(city,".csv"))
        else
            ct = get_POI(string(city,".osm"))
        end

        city_center = center_dict[city]

        push!(dfs,ct)
        push!(centers,city_center)
        push!(ixs,AttractivenessSpatIndex(dfs[index],get_range=a->distance_to_analyse))
        push!(points,generate_sectors(num_of_sectors,distance_for_sector,
                                                            city_center,points_in_sector,
                                                                city_boundaries[index][1],
                                                                city_boundaries[index][2]))

        for attribute in list_of_attributes
            attr = calculate_attractiveness_of_sector(points[index],ixs[index], attribute)
            attr_of_cities[city][attribute] = min_max_scaling(attr)
        end
    end
    return attr_of_cities
end


"""
Determines whether a point lies within the city boundaries

- 'city_boundaries'::Vector{Luxor.Point} - boundaries of the city
- 'point'::Luxor.Point - the examined point
"""
function check_if_inside(city_boundaries::Vector{Luxor.Point}, point::Luxor.Point)
    return isinside(point,city_boundaries; allowonedge=true)
end
