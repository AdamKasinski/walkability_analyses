using OpenStreetMapX
using OSMToolset


function generate_circle_of_points(distance::Int,centre::LLA,num_of_points::Int)
    points = Array{Any}(undef, num_of_points)
    radian::Float64 = 360/num_of_points*π/180
    for point in 1:num_of_points
        points[point] = find_point_in_distance(distance,centre,point*radian)
    end
    return points
end

function find_point_in_distance(distance::Int, centre::LLA, radian::Float64)
    return LLA(ENU(distance*cos(radian),distance*sin(radian),0),centre)
end