using Downloads
using OSMToolset
using OpenStreetMapX
using Downloads
using GZip
using DataFrames
using CSV
using HTTP
using JSON
using EzXML
using DataFrames
using Statistics
# TODO jest balagan z bibliotekami, tu jest uzywane readxml a nie jest importowane (dodalem import)

""" 
Retrieves the area defined by the outermost vertices of the specified city.

- 'city'::String: The name of the city for which to download the boundary.
- 'admin_level'::String: The administrative level of the area being searched.
"""
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
    return "$city.osm"
end

""" 
Downloads the relation ID of a specified city.

- 'city'::String: The name of the city for which to download the relation ID.
- 'admin_level'::String: The administrative level of the area being searched.
"""
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
Downloads the boundaries of a specified city.

- 'city'::String: The name of the city for which to download boundaries.
- 'admin_level'::String: The administrative level of the area being searched.
"""
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


"""
Downloads the map of a specified city from BBBike.
- 'city'::String: The name of the city for which to download the map.
"""
function download_data_from_bbbike(city::String)
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

"""
Creates a map from an OSM file.

- 'file'::String: The name of the file used to create the map.
"""
function create_map(file::String)
    return get_map_data(file,use_cache = false)
end

"""
Saves points of interest (POI) from a DataFrame to a CSV file.

- 'df'::DataFrame: The DataFrame containing the data to be saved.
- 'save_as'::String: The name of the CSV file where the data will be saved.
"""
function save_asm(df::DataFrame,save_as::String)
    if save_as != ""
        CSV.write(save_as,df)
    end
end

"""
Creates a Points of Interest (POI) file based on an OSM file.

- 'file'::String: The name of the OSM file to process.
- 'scrape_config': The configuration file specifying how to extract POIs.
- 'save_as'::String: The name of the CSV file where the POI table will be saved.
"""
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

"""
Downloads an OSM file containing the boundaries of a specified city.

- 'city'::String: The name of the city for which the OSM file is downloaded.
"""
function download_boundaries_file(city::String,admin_level::String)

    if isfile(string(city,"_boundaries.osm"))
        return "The file is already downloaded"
    end
    query = """
        [out:xml];
        area[name="$city"]->.searchArea;
        (
        relation(area.searchArea)["type"="boundary"]["boundary"="administrative"]["admin_level"="$admin_level"]["name"="$city"];
        );
        out body;
        >;
        out skel qt;
    """
    url="http://overpass-api.de/api/interpreter/"

    response = HTTP.post(url,body=query)

    if response.status == 200
        open(string(city,"_boundaries.osm"), "w") do file
            write(file, String(response.body))
        end
    else
        println("Failed to download $city boundaries data")
    end
    return string(city,"_boundaries.osm")
end

"""
Extracts city boundaries from an OSM file in ENU format.

- 'filename'::String: The name of the file containing the boundaries.
"""
function extract_points_ENU(filename::String)
    osm_file = readxml(filename)
    #jako posrednich struktur uzywac ramek danych ze wzgledu na latwosc tesotwania
    nodes = DataFrame((;id=parse(Int, node["id"]), lat=parse(Float64, node["lat"]),
                    lon=parse(Float64, node["lon"] ))  for node in findall("//node", osm_file))
    #punkt referencyjny dla mapy, potem zrobic jako tez mozliwy parametr
    reflla = LLA(mean(nodes.lat),mean(nodes.lon),0.0)
    idtoENU = Dict{Int,ENU}(nodes.id .=> ENU.(LLA.(nodes.lat,nodes.lon,0.0),Ref(reflla)))

    ways_refs = Dict{Int, Vector{Int}}()
    # find all tags <way ...>...</way>
    for way in findall("//way", osm_file)
        id = parse(Int, way["id"])
        ways_refs[id] = [parse(Int, nd["ref"]) for nd in findall("nd",way)]
    end

    rela = findall("//relation[tag[@k='boundary' and @v='administrative']]", osm_file)[1]

    # find all tags member in the rela with <member type="way" role="outer"/>
    res = DataFrame()
    adminname = findall("tag[@k='name']", rela)[1]["v"]
    for member in findall("member[@type='way' and @role='outer']", rela)
        wayid = parse(Int, member["ref"])
        nodes = ways_refs[wayid]
        append!(res,DataFrame(adminname=adminname, wayid=wayid, nodes=nodes, x=getX.(getindex.(Ref(idtoENU),nodes)), y=getY.(getindex.(Ref(idtoENU),nodes) )))
    end
    res
end

"""
Extracts city boundaries from an OSM file in LLA format.

- 'filename'::String: The name of the file containing the boundaries.
"""

function extract_points_LLA(filename::String)
    osm_file = readxml(filename)
    #jako posrednich struktur uzywac ramek danych ze wzgledu na latwosc tesotwania
    nodes = DataFrame((;id=parse(Int, node["id"]), lat=parse(Float64, node["lat"]),
                    lon=parse(Float64, node["lon"] ))  for node in findall("//node", osm_file))
    #punkt referencyjny dla mapy, potem zrobic jako tez mozliwy parametr
    reflla = LLA(mean(nodes.lat),mean(nodes.lon),0.0)
    idtoLLA = Dict{Int,LLA}(nodes.id .=> LLA.(nodes.lat,nodes.lon,0.0))

    ways_refs = Dict{Int, Vector{Int}}()
    # find all tags <way ...>...</way>
    for way in findall("//way", osm_file)
        id = parse(Int, way["id"])
        ways_refs[id] = [parse(Int, nd["ref"]) for nd in findall("nd",way)]
    end

    rela = findall("//relation[tag[@k='boundary' and @v='administrative']]", osm_file)[1]

    # find all tags member in the rela with <member type="way" role="outer"/>
    res = DataFrame()
    adminname = findall("tag[@k='name']", rela)[1]["v"]
    for member in findall("member[@type='way' and @role='outer']", rela)
        wayid = parse(Int, member["ref"])
        nodes = ways_refs[wayid]
        append!(res,DataFrame(adminname=adminname, wayid=wayid, nodes=nodes, x=getX.(getindex.(Ref(idtoLLA),nodes)), y=getY.(getindex.(Ref(idtoLLA),nodes) )))
    end
    res
end

function get_city_centre(boundaries_file::String)
    osm_file = readxml(boundaries_file)
    centre_ref = findfirst("//relation/member[@type='node' and @role='admin_centre']",osm_file)["ref"]
    centre_node = findfirst("//node[@id='$centre_ref']",osm_file)
    lat = parse(Float64, centre_node["lat"])
    lon = parse(Float64, centre_node["lon"])
    return LLA(lat,lon,0)
end

