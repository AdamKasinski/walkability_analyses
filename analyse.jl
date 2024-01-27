using OpenStreetMapX
using OSMToolset

"""
generate n points around the center within a distance

- 'distance'::Int - radius of circle in meters
- 'centre'::LLA - centre of the circle
- 'num_of_points'::Int - number of points to generate
- 'within'::Bool - "yes" - points generated on the circumference  
                    "no" - point generated inside the circle,
                           the nearest point at a distance of 100 meters 
"""
function generate_circle_of_points(distance::Int,centre::LLA,num_of_points::Int,within::Bool)
    radian::Float64 = 360/num_of_points*π/180
    if within
        points = [find_point_in_distance(distance, centre, point * radian) for 
                                                    point in 1:num_of_points]
    else 
        points = [find_point_in_distance(distance, centre, point * radian) for 
                                                    point in 1:num_of_points]
    end
    return points
end

"""
generate a point at a specified distance from the center
"""
function find_point_in_distance(distance::Int, centre::LLA, radian::Float64)
    return LLA(ENU(distance*cos(radian),distance*sin(radian),0),centre)
end


"""
generate a point on a segment of a specified length 
"""

function find_point_in_distance(radius::Int, centre::LLA, radian::Float64)
    distance = rand(100:radius)
    return LLA(ENU(distance*cos(radian),distance*sin(radian),0),centre)
end