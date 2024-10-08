using Downloads
using OSMToolset
using OpenStreetMapX
using Downloads
using DataFrames
using CSV
using HTTP
using JSON
using EzXML
using DataFrames
using Statistics
include("sectors.jl")

DATA_PATH = "../data"

""" 
Retrieves the area defined by the outermost vertices of the specified city.

- 'city'::String: The name of the city for which to download the boundary.
- 'admin_level'::String: The administrative level of the area being searched.
- 'dir'::String
"""
function download_city_with_bounds(city::String, admin_level::String;dir=DATA_PATH)
    if isfile(string(dir,"/","$city.osm"))
        return "The file is already downloaded"
    end
    bounds = get_city_bounds(city,admin_level)
    min_lon = bounds["minlon"]
    max_lon = bounds["maxlon"]
    min_lat = bounds["minlat"]
    max_lat = bounds["maxlat"]
    f = Downloads.download("https://overpass-api.de/api/map?bbox=$min_lon,$min_lat,$max_lon,$max_lat")
    mv(f, string(dir,"/","$city.osm"))
    return string(dir,"/","$city.osm")
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
- 'dir'::String
"""
function get_city_bounds(city_name::String,level::String;dir=DATA_PATH)
    
    if isfile(string(dir,"/",city_name,"_bounds.csv"))
        df = DataFrame(CSV.File(string(dir,"/",city_name,"_bounds.csv")))
        return Dict("maxlon" => df.maxlon[1],
                    "minlon" => df.minlon[1],
                    "maxlat" => df.maxlat[1],
                    "minlat" => df.minlat[1])
    end
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
    bds = j["elements"][1]["bounds"]
    CSV.write(string(dir,"/",city_name,"_bounds.csv"),DataFrame(bds))
    return bds
end


"""
Downloads the map of a specified city from BBBike.
- 'city'::String: The name of the city for which to download the map.
- 'dir'::String
"""
function download_data_from_bbbike(city::String;dir=DATA_PATH)
    if isfile(string(dir,"/",city,".osm"))
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
- 'dir'::String
"""
function create_map(file::String;use_cache = true,trim_to_connected_graph=true,dir=DATA_PATH)
    file = string(dir,"/",file)
    return get_map_data(file,use_cache = use_cache,only_intersections=false,
                        trim_to_connected_graph=trim_to_connected_graph)
end

"""
Saves points of interest (POI) from a DataFrame to a CSV file.

- 'df'::DataFrame: The DataFrame containing the data to be saved.
- 'save_as'::String: The name of the CSV file where the data will be saved.
- 'dir'::String
"""
function save_asm(df::DataFrame,save_as::String;dir=DATA_PATH)
    save_as=string(dir,"/",save_as)
    if save_as != ""
        CSV.write(save_as,df)
    end
end

"""
Creates a Points of Interest (POI) file based on an OSM file.

- 'file'::String: The name of the OSM file to process.
- 'scrape_config': The configuration file specifying how to extract POIs.
- 'save_as'::String: The name of the CSV file where the POI table will be saved.
- 'dir'::String
"""
function get_POI(filename::String,scrape_config = nothing, save_as::String = "";dir=DATA_PATH) 
    file = string(dir,"/",filename)
    save_as = string(dir,"/",save_as)
    if endswith(file,"osm")
        if isnothing(scrape_config)
            scrp_config = OSMToolset.ScrapePOIConfig()
        else
            scrp_config = OSMToolset.ScrapePOIConfig(DataFrame(CSV.File(scrape_config)))
        end
        fl = OSMToolset.find_poi(file,scrp_config)
        save_asm(fl,save_as)
        return fl
    elseif endswith(file,"csv")
        return DataFrame(CSV.File(file))
    end
end

"""
Downloads an OSM file containing the boundaries of a specified city.

- 'city'::String: The name of the city for which the OSM file is downloaded.
- 'admin_level"::String
- 'dir'::String
"""
function download_boundaries_file(city::String,admin_level::String;dir=DATA_PATH)

    if isfile(string(dir,",",city,"_boundaries.osm"))
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
        open(string(dir,"/",city,"_boundaries.osm"), "w") do file
            write(file, String(response.body))
        end
    else
        println("Failed to download $city boundaries data")
    end
    return string(dir,"/",city,"_boundaries.osm")
end

"""
Extracts city boundaries from an OSM file in ENU format.

- 'filename'::String: The name of the file containing the boundaries.
- 'dir'::String
"""
function extract_points_ENU(filename::String,centre;dir=DATA_PATH)
    file = string(dir,"/",filename)
    osm_file = readxml(file)
    #jako posrednich struktur uzywac ramek danych ze wzgledu na latwosc tesotwania
    nodes = DataFrame((;id=parse(Int, node["id"]), lat=parse(Float64, node["lat"]),
                    lon=parse(Float64, node["lon"] ))  for node in findall("//node", osm_file))
    #punkt referencyjny dla mapy, potem zrobic jako tez mozliwy parametr
    reflla = centre
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
    a = 1
    for member in findall("member[@type='way' and @role='outer']", rela)
        wayid = parse(Int, member["ref"])
        nodes = ways_refs[wayid]
        x_vals = getX.(getindex.(Ref(idtoENU),nodes))
        y_vals = getY.(getindex.(Ref(idtoENU),nodes))
        if a > 1
            first_point = (x_vals[1], y_vals[1])
            last_point = (x_vals[end],y_vals[end])
            last_added_point = (res.x[end],res.y[end])
            rev = argmin(
                [abs(last_point[1]-last_added_point[1])+
                abs(last_point[2]-last_added_point[2]),
                abs(first_point[1]-last_added_point[1])+
                abs(first_point[2]-last_added_point[2])])
            if rev == 1
                x_vals = reverse(x_vals)
                y_vals = reverse(y_vals)
            end
        end
        a+=1
        append!(res,DataFrame(adminname=adminname, wayid=wayid, nodes=nodes, 
                x=x_vals,y=y_vals))
    end
    res
end

"""
Extracts city boundaries from an OSM file in LLA format.

- 'filename'::String: The name of the file containing the boundaries.
- 'dir'::String
"""
function extract_points_LLA(filename::String, centre;dir=DATA_PATH)
    file = string(dir,"/",filename)
    osm_file = readxml(file)
    #jako posrednich struktur uzywac ramek danych ze wzgledu na latwosc tesotwania
    nodes = DataFrame((;id=parse(Int, node["id"]), lat=parse(Float64, node["lat"]),
                    lon=parse(Float64, node["lon"] ))  for node in findall("//node", osm_file))
    #punkt referencyjny dla mapy, potem zrobic jako tez mozliwy parametr
    reflla = centre #LLA(mean(nodes.lat),mean(nodes.lon),0.0)
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
"""
- 'boundaries_file'::String,
- 'dir'::String
"""
function get_city_centre(boundaries_file::String;dir=DATA_PATH)
    osm_file_path = string(dir,"/",boundaries_file)
    osm_file = readxml(osm_file_path)
    centre_ref = findfirst("//relation/member[@type='node' and @role='admin_centre']",osm_file)["ref"]
    centre_node = findfirst("//node[@id='$centre_ref']",osm_file)
    lat = parse(Float64, centre_node["lat"])
    lon = parse(Float64, centre_node["lon"])
    return LLA(lat,lon,0)
end

function prepare_city_map(city_name::String, 
                admin_level::String, search_area::Int,
                wilderness_distance,shape;calculate_percent=false,
                distance_sectors=0.0,num_of_points=0,num_of_sectors=0,
                scrape_config = nothing,
                calculate_attractiveness::Function=OSMToolset.calculate_attractiveness, 
                distance=OpenStreetMapX.distance,
                rectangle_boundaries = [], in_admin_bounds=true,dir=DATA_PATH)
    
    download_city_with_bounds(city_name,admin_level;dir=dir)
    
    
    if isfile(string(dir,"/","$city_name.csv"))
        df_city = get_POI("$city_name.csv",scrape_config;dir=dir)
    else
        df_city = get_POI("$city_name.osm",scrape_config,"$city_name.csv";dir=dir)
    end

    download_boundaries_file(city_name,admin_level;dir=dir)
    boundaries_file = string(city_name,"_boundaries.osm")
    city_map = create_map("$city_name.osm";dir=dir)
    city_centre = OpenStreetMapX.center(city_map.bounds)
    admin_city_centre = get_city_centre(boundaries_file;dir=dir)
    city_boundaries = extract_points_ENU(boundaries_file,admin_city_centre;dir=dir)
    ix_city = AttractivenessSpatIndex(df_city,get_range=a->search_area)
    if rectangle_boundaries == []
        rectangle_boundaries = get_city_bounds(city_name,admin_level;dir=dir)
    end
    nodes_for_tree = change_ENU_center(city_map.nodes,city_centre, admin_city_centre)
    city_tree = generate_index(wilderness_distance, nodes_for_tree)
    min_point = ENU(LLA(rectangle_boundaries["minlat"],
                        rectangle_boundaries["minlon"],0),admin_city_centre)
    max_point = ENU(LLA(rectangle_boundaries["maxlat"],
                        rectangle_boundaries["maxlon"],0),admin_city_centre)

    if calculate_percent
        dist_min = OpenStreetMapX.distance(min_point,ENU(0,0,0))
        dist_max = OpenStreetMapX.distance(max_point,ENU(0,0,0))
        distance_sectors = maximum([dist_min,dist_max])/100
        num_of_sectors = 100
    end

    shape_arguments = get_shape_args(shape, city_boundaries, 
                                    city_tree,distance_sectors, num_of_points, 
                                    num_of_sectors,rectangle_boundaries,
                                    min_point, max_point,
                                    in_admin_bounds=in_admin_bounds)
    if shape == "circle"
        points = generate_sectors(shape_arguments...)
    elseif shape == "rectangle"
        points = generate_rectangles(shape_arguments...)
    end

    return points,
        admin_city_centre,
        ix_city,
        df_city,
        city_boundaries,
        city_map

    #return City_points(points, 
    #                    admin_city_centre, 
    #                    ix_city, 
    #                    df_city, 
    #                    city_boundaries, 
    #                    city_map)
end


function prepare_city_sectors(city_name::String, admin_level::String, 
                            search_area::Int,attr::Symbol,
                            wilderness_distance,num_of_points;
                            calculate_percent=true, distance_sectors=0.0,
                            num_of_sectors=0, scrape_config = nothing,
                calculate_attractiveness::Function=OSMToolset.calculate_attractiveness, 
                            distance=OpenStreetMapX.distance,
                            rectangle_boundaries = [],dir=DATA_PATH)
    
    download_city_with_bounds(city_name,admin_level;dir=dir)

    if isfile(string(dir,"/","$city_name.csv"))
        df_city = get_POI("$city_name.csv",scrape_config;dir=dir)
    else
        df_city = get_POI("$city_name.osm",scrape_config,"$city_name.csv";dir=dir)
    end

    download_boundaries_file(city_name,admin_level;dir=dir)
    boundaries_file = string(city_name,"_boundaries.osm")
    city_map = create_map("$city_name.osm";dir=dir)
    city_centre = OpenStreetMapX.center(city_map.bounds)
    admin_city_centre = get_city_centre(boundaries_file;dir=dir)
    city_boundaries = extract_points_ENU(boundaries_file,admin_city_centre;dir=dir)
    ix_city = AttractivenessSpatIndex(df_city,get_range=a->search_area)
    if rectangle_boundaries == []
        rectangle_boundaries = get_city_bounds(city_name,admin_level;dir=dir)
    end
    nodes_for_tree = change_ENU_center(city_map.nodes,city_centre, admin_city_centre)
    city_tree = generate_index(wilderness_distance, nodes_for_tree)
    min_point = ENU(LLA(rectangle_boundaries["minlat"],
                        rectangle_boundaries["minlon"],0),admin_city_centre)
    max_point = ENU(LLA(rectangle_boundaries["maxlat"],
                        rectangle_boundaries["maxlon"],0),admin_city_centre)

    if calculate_percent
        dist_min = OpenStreetMapX.distance(min_point,ENU(0,0,0))
        dist_max = OpenStreetMapX.distance(max_point,ENU(0,0,0))
        distance_sectors = maximum([dist_min,dist_max])/100
        num_of_sectors = 100
    end

    shape_arguments = get_shape_args("circle", city_boundaries, 
                                    city_tree,distance_sectors, num_of_points, 
                                    num_of_sectors,rectangle_boundaries,
                                    min_point, max_point)

    return City_sectors(generate_sectors(shape_arguments...),
                                        admin_city_centre, 
                                        ix_city, 
                                        df_city, 
                                        city_boundaries, 
                                        city_map)

end


struct City_sectors
    sectors
    admin_city_centre 
    ix_city
    df_city
    city_boundaries
    city_map
end

struct City_points
    points
    admin_city_centre
    ix_city
    df_city
    city_boundaries
    city_map
end