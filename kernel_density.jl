# 1. wyznacz wszystkie punkty w mieście - weź napisaną funkcję
# 2. wyznacz wszystkie amenities 
# 3. zrób funkcję, która policzy odległość euklidesową między punktami
# 4. policz odległości między wszystkimi amenities a punktem
# 5. użyj KDE
# 6. przypisz wartość

using DataFrames
using OpenStreetMapX
using KernelDensity
include("prepare_data.jl")

function get_amenity_values(city_poi::DataFrame,amenity::String)
    return city_poi[city_poi.value .== amenity, [:lat,:lon]]
end

function get_amenity_group(city_poi::DataFrame,amenity::String)
    return city_poi[city_poi.group .== amenity, [:lat,:lon]]
end

function kernel_density(city_sector::City_points, attribute::String)
    dim1 = size(city_sector.points[:,1])[1]
    dim2 = size(city_sector.points[1,:])[1]
    amenities = get_amenity_group(city_sector.df_city,attribute)
    combined = [LLA(amenities.lat[i], amenities.lon[i], 0.0) for i in 1:nrow(amenities)]
    ENUs = zeros(length(combined),2)
    for point in eachindex(combined)
        pt = ENU(combined[point], city_sector.admin_city_centre)
        ENUs[point,1] = pt.east
        ENUs[point,2] = pt.north
    end
    kde_rslt = kde(ENUs)
    easts = [city_sector.points[i, j].east for i in 1:dim1, j in 1:dim2]
    norths = [city_sector.points[i, j].north for i in 1:dim1, j in 1:dim2]
    easts = reshape(easts,(dim1*dim2,1))
    norths = reshape(norths,(dim1*dim2,1))
    pdfs = [pdf(kde_rslt, i[1], i[2]) for i in zip(easts,norths)]
    return reshape(pdfs,(dim1,dim2))
end