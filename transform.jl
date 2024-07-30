using OpenStreetMapX
using Statistics



function to_zero(elem)
    if elem == Inf || elem < 0
        return 0
    end
    return elem
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

function matrix_log_scaling(attrs)
    return to_zero.(log.(attrs))
end