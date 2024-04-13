using Match
using OpenStreetMapX
using OSMToolset
using Statistics
using Luxor

"""
The function generate n sectors inside the city

- 'distance'::Int - numer of sector to generate
- 'size_of_sector'::Int - radius of each sector
- 'centre'::LLA - centre of the map
- 'num_of_points'::Int - number of points to generate in each sector
- 'city_boundaries_north'::Vector{Float64 - latitudes of the city boundaries
- 'city_boundaries_east'::Vector{Float64} - longitudes of the city boundaries
"""
function generate_sectors(city_boundaries_east::Vector{Float64},
                        city_boundaries_north::Vector{Float64},tree,
                        num_of_points::Int, num_of_sectors::Int,distance::Float64)

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

function generate_rectangles(boundaries_east, boundaries_north, 
                            rectangle_bounds,distance, tree, min_point, max_point)

    city_boundaries = Luxor.Point.(boundaries_east,boundaries_north)
    x_distance = max_point.east - min_point.east
    y_distance = max_point.north - min_point.north

    num_of_x = ceil(Int,x_distance/distance)
    num_of_y = ceil(Int,y_distance/distance)

    x_cords = range(min_point.east, stop=max_point.east, length=num_of_x)
    y_cords = range(min_point.north, stop=max_point.north, length=num_of_y)
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


function get_shape_args(shape, city_boundaries, 
                        city_tree,distance, num_of_points, 
                        num_of_sectors,rectangle_boundaries,min_point, max_point)

    @match shape begin
        $"circle" => return (
                            city_boundaries.x,
                            city_boundaries.y,
                            city_tree,
                            num_of_points,
                            num_of_sectors,
                            distance,
                        )
        $"rectangle" => return (
                            city_boundaries.x,
                            city_boundaries.y,
                            rectangle_boundaries,
                            distance,
                            city_tree,
                            min_point,
                            max_point
                        )
    end
end
