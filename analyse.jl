using OpenStreetMapX
using OSMToolset
using Statistics


"""
generate n points around the center within boundries 

- 'boundries'::Int - segment on which a point will be drawn
- 'centre'::LLA - centre of the circle
- 'num_of_points'::Int - number of points to generate
"""

function generate_points_in_sector(boundries::Tuple{Int,Int},centre::LLA,num_of_points::Int)
    radian::Float64 = 360/num_of_points*π/180
    points = [find_point_within_boundries(boundries, centre, point * radian) for point in 1:num_of_points]
    return points
end

"""
generate n sectors

- 'num_of_sectors'::Int - numer of sector to generate
- 'size_of_sector'::Int - radius of each sector
- 'centre'::LLA - centre of the map
- 'num_of_points'::Int - number of points to generate in each sector
"""

function generate_sectors(num_of_sectors::Int,size_of_sector::Int,centre::LLA,num_of_points::Int)
    sectors = Array{Any,2}(undef,num_of_sectors,num_of_points)
    for sector in 1:num_of_sectors
        boundries::Tuple{Int,Int} = ((sector-1)*size_of_sector+1,sector*size_of_sector)
        sectors[sector,:] = generate_points_in_sector(boundries,centre,num_of_points)
    end
    return sectors
end 

"""
generate a point on a segment of a specified length 
"""
function find_point_within_boundries(boundries::Tuple{Int,Int}, centre::LLA, radian::Float64)
    distance = rand(boundries[1]:boundries[2])
    return LLA(ENU(distance*cos(radian),distance*sin(radian),0),centre)
end

"""
- 'points'::Array{Any,2} - matrix with LLA points
- 'attractivenessSpatIndex'::attractivenessSpatIndex 
- 'attribute'::Symbol - The category that will be used to calculate attractiveness 
                        (:education, :entertainment, :healthcare, :leisure, :parking, 
                        :restaurants, :shopping, :transport)
"""
function calculate_attractiveness_of_sector(points_matrix,attractivenessSpatIndex,
                                                                attribute::Symbol)
    dim1 = size(points_matrix,1)
    dim2 = size(points_matrix,2)
    attract = Array{Float64}(undef, dim1)
    for i in 1:dim1
        attr = zeros(Float64,dim2)
        for j in 1:dim2
            attr[j] = getfield(OSMToolset.attractiveness(
                attractivenessSpatIndex,points[i,j]),attribute)
        end
        attract[i] = mean(attr)
    end
    return attract
end