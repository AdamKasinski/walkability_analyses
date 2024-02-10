using OpenStreetMapX
using OSMToolset
using Statistics
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

function workflow(list_of_cities,num_of_sectors,distance_for_sector,points_in_sector,
                    distance_to_analyse,csv)
    maps = []
    dfs = []
    centers = []
    ixs = []
    points = []
    attr_of_cities = []
    stand_cities = []
    x_axis = []
    for city in list_of_cities
        download_data(city)
    end

    centers = [LLA(50.061692315544654, 19.939496620660737),
    LLA(49.196664523003115, 16.60804112914713),
    LLA(50.29388096424714, 18.66566269980933)]

    a = 1
    for city in list_of_cities
        map_of_city = get_map_data(string(city,".osm"))
        center = OpenStreetMapX.center(map_of_city.bounds)
        if csv
            ct = get_POI(string(city,".csv"))
        else
            ct = get_POI(string(city,".osm"))
        end

        push!(dfs,ct)
        push!(centers,center)
        push!(ixs,AttractivenessSpatIndex(dfs[end],get_range=a->distance_to_analyse))
        push!(points,generate_sectors(num_of_sectors,distance_for_sector,
                                                            center,points_in_sector))
        push!(attr_of_cities,calculate_attractiveness_of_sector(points[end],ixs[end],
                                                                        :shopping))
        push!(stand_cities,min_max_scaling(attr_of_cities[end]))
        a+=1                                                                                                                                     
    end
    return stand_cities
end

#TODO: 1) add dicitonary with ceneters of the cities - bounds.center does not work correct
#         for that task
#      2) export the lists to file
#      3) add more attributes
#      4) generate PDF
#      5) change config file
#      6) add subcategories