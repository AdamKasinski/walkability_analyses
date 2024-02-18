using Downloads
using OSMToolset
using OpenStreetMapX
using Downloads
using GZip
using DataFrames
using CSV
using HTTP
using JSON


function download_city_with_bounds(city::String, admin_level::String)
    if isfile("$city.osm")
        return "The file is already downloaded"
    end
    bounds = get_city_bounds(city,admin_level)
    min_lon = bounds["minlon"]
    max_lon = bounds["maxlon"]
    min_lat = bounds["minlat"]
    max_lat = bounds["maxlat"]
    f = Downloads.download("https://overpass-api.de/api/map?bbox=$min_lon,$min_lat,$max_lon,$max_lat")
    mv(f, "$city.osm")
end


"""
method needs to be revised
"""
function __download_data_api(city::String,admin_level = "8")
    if isfile(string(city,".osm"))
        return "The file is already downloaded"
    end
    relation_id = get_relation_id(city,admin_level)
    download_data_relation(city,relation_id)
    return get_city_bounds(city,admin_level)
end

function get_relation_id(city_name::String, admin_level::String)
    query = """
    [out:json];
    area[name="$city_name"]->.searchArea;
    relation(area.searchArea)["boundary"="administrative"]["admin_level"="$admin_level"];
    out ids;
    """
    encoded_query = HTTP.escapeuri(query)
    url = "http://overpass-api.de/api/interpreter?data=$encoded_query"
    response = HTTP.get(url)
  
    if response.status == 200
        data = JSON.parse(String(response.body))      
        return get(data["elements"][1], "id", nothing)
    else
        return -1
    end
  end

  """
  method needs to be revised
  """
function __download_data_relation(city_name::String,relation_id::Int)
    f = 3600000000 + relation_id
    query = """
        [out:xml];
        area($f)->.searchArea;
        (
        node(area.searchArea);
        way(area.searchArea);
        relation(area.searchArea);
        );
        (._; >;);
        out meta;
    """

    overpass_url = "http://overpass-api.de/api/interpreter/"
    response = HTTP.post(overpass_url, body = query)
    
    if response.status == 200
        open(string(city_name,".osm"), "w") do file
            write(file, String(response.body))
        end
    else
        println("Failed to download OSM data")
    end
end

function get_city_bounds(city_name::String,level::String)
    query = """
    [out:json];
    area['admin_level'='$level']['name'='$city_name'];
    (relation['admin_level'='$level'](area););
    out geom;
    """
    overpass_url = "http://overpass-api.de/api/interpreter/"
    response = HTTP.post(overpass_url, body = query)
    a = String(response.body)
    j = JSON.parse(a)
    return j["elements"][1]["bounds"]  
end

function download_data(city::String)
    if isfile(string(city,".osm"))
        return "The file is already downloaded"
    else
        url = string("https://download.bbbike.org/osm/bbbike/",city,"/",city,".osm.gz")
        output =  tempname()*".gz"
        Downloads.download(url,output)
        tname = string(city,".osm")
        buf = Vector{UInt8}(undef, 1024)
        GZip.open(output, "r") do f
            open(tname, "w") do out
                while !eof(f)
                    nb = readbytes!(f, buf)
                    write(out, @view buf[1:nb])
                end
            end
        end
        rm(output; recursive=false)
    end
end

function create_map(file::String)
    return get_map_data(file,use_cache = false)
end

function save_asm(file::DataFrame,save_as::String)
    if save_as != ""
        CSV.write(save_as,file)
    end
end

function get_POI(file::String,scrape_config = nothing, save_as::String = "")
    if endswith(file,"osm")
        if isnothing(scrape_config)
            scrape_config = OSMToolset.ScrapePOIConfig()
        end
        fl = OSMToolset.find_poi(file;scrape_config)
        save_asm(fl,save_as)
        return fl
    elseif endswith(file,"csv")
        return DataFrame(CSV.File(file))
    end
end

function get_boundries_points(city::String)
    query = """
    [out:xml];
    area[name="$city"];
    (
    relation["type"="boundary"]["name"="$city"];
    );
    (._; >;);
    out body;
    """
    url="http://overpass-api.de/api/interpreter/"
    response = HTTP.post(url,body=query)

    if response.status == 200
        open(string(city,"_boundries.osm"), "w") do file
            write(file, String(response.body))
        end
    else
        println("Failed to download $city boundries data")
    end

    osm_file = readxml(string(city,"_boundries.osm"))

    nodes_bounds = []
    
    for node in findall("//node", osm_file)
        lat = parse(Float64, node["lat"])
        lon = parse(Float64, node["lon"])
        push!(nodes_bounds, (lat, lon))
    end
    
    return nodes_bounds
end
