using OpenStreetMapX
using OSMToolset
using Statistics

# TODO jest balagan z kolejnoscia importow bo jupyter notebook tez importuje prepare_data.jl
# W kodzie trzeba miec porzadek bo inaczej ciezko goutrzymac i aktualizwoac

include("prepare_data.jl")

"""
generate n sectors

- 'distance'::Int - numer of sector to generate
- 'size_of_sector'::Int - radius of each sector
- 'centre'::LLA - centre of the map
- 'num_of_points'::Int - number of points to generate in each sector
"""

function generate_sectors(num_of_sectors::Int,distance::Int,centre::LLA,num_of_points::Int)

    sectors = Array{LLA,2}(undef,num_of_sectors,num_of_points)
    for sector in 1:num_of_sectors
        sectors[sector,:] = generate_points_in_sector(distance*sector,centre,num_of_points)
    end
    return sectors
end

"""
generate n points around the center at a distance

- 'distance'::Int - distance at which points will be generated
- 'centre'::LLA - centre of the circle
- 'num_of_points'::Int - number of points to generate
"""

function generate_points_in_sector(distance::Int,centre::LLA,num_of_points::Int)
    radian::Float64 = 360/num_of_points*π/180
    points = [find_point_at_distance(distance, centre, point * radian)
                                            for point in 1:num_of_points]
    return points
end


"""
generate a point at a distance n from the center
"""
function find_point_at_distance(radius::Int,centre::LLA, radian::Float64)
    return LLA(ENU(radius*cos(radian),radius*sin(radian),0),centre)

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
    attrs = [zeros(Float64,dim2) for _ in 1:Threads.nthreads()]
    Threads.@threads for i in 1:dim1
        attr = attrs[Threads.threadid()]
        fill!(attr, 0.0)
        for j in 1:dim2
            attr[j] = getfield(OSMToolset.attractiveness(
                attractivenessSpatIndex,points_matrix[i,j]),attribute)
        end
        attract[i] = mean(attr)
    end
    return attract
end

function min_max_scaling(vec::Vector{Float64})
    mins = minimum(vec)
    maxs = maximum(vec)
    (vec.-mins)/(maxs-mins)
end

function create_comparison(list_of_cities,num_of_sectors,distance_for_sector,
                                points_in_sector, distance_to_analyse,csv, center_dict,
                                list_of_attributes)

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
                                                            city_center,points_in_sector))

        for attribute in list_of_attributes
            attr = calculate_attractiveness_of_sector(points[index],ixs[index], attribute)
            attr_of_cities[city][attribute] = min_max_scaling(attr)
        end
    end
    return attr_of_cities
end


function calculate_bounds(poi_df::DataFrame)
    max_lat = maximum(poi_df[poi_df.value .!= "stop_position","lat"])
    min_lat = minimum(poi_df[poi_df.value .!= "stop_position","lat"])
    max_lon = maximum(poi_df[poi_df.value .!= "stop_position","lon"])
    min_lon = minimum(poi_df[poi_df.value .!= "stop_position","lon"])
    return min_lat,min_lon,max_lat,max_lon
end