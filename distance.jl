using OpenStreetMapX
using OSMToolset

function exp_attractiveness(a::AttractivenessMetaPOI, poidistance::Number)
    
    if poidistance >= a.range
        return 0.0
    else
        return a.influence * exp(-(a.range/poidistance))
    end
end
