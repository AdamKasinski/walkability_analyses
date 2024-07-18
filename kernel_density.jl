# 1. wyznacz wszystkie punkty w mieście - weź napisaną funkcję
# 2. wyznacz wszystkie amenities 
# 3. zrób funkcję, która policzy odległość euklidesową między punktami
# 4. policz odległości między wszystkimi amenities a punktem
# 5. użyj KDE
# 6. przypisz wartość

using DataFrames
using OpenStreetMapX
using KernelDensity


function get_amenity_values(city_poi::DataFrame,amenity::String)
    return city_poi[city_poi.value .== amenity, [:lat,:lon]]
end

function get_amenity_group(city_poi::DataFrame,amenity::String)
    return city_poi[city_poi.group .== amenity, [:lat,:lon]]
end
