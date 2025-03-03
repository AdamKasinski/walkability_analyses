using Luxor
using Colors
using Plots
using IterTools
using DataFrames
using OpenStreetMapX
using LightOSM
using KernelDensity
using Downloads
include("../kernel_density.jl")
include("../distance.jl")
include("../prepare_data.jl")
include("../analyse.jl")
include("../plots.jl")
include("/home/adamkas/Julia/map_analyses/OSMXGraph/src/OSMXGraph.jl")
using .OSMXGraph

percentiles = Dict()

#cities1 = ["Kielce","Kraków","Warszawa","Brno","Vienna","Toronto"]
#cities2 = ["Trieste","Vilnius","Zagreb","Sofia","Sewilla","Seattle"]
#cities3 = ["San Diego","San Francisko","Sacramento","Rome", "Quebec City"]
#cities4 = ["Prague","Poznan","Pittsburgh","Ottawa","Oslo", "New York"]
#cities5 = ["Naples", "Munich", "Montreal", "Milan", "Miami", "Madrid"]
#cities6 = ["Lyon", "Los Angeles", "Lisbon","Istanbul","Hamburg","Hague"]
#cities7 = ["Dublin","Detroit","Denver","Dallas","Copenhagen","Chicago"]
#cities8 = ["Budapest","Bucharest","Bratislava","Boston","Belgrad","Barcelona"]
#cities9 = ["Baltimore","Austin", "Atlanta", "Athens","Ankara","Amsterdam"]
#
#cities_list = [cities1, cities2, cities3, cities4, cities5, cities6, cities7, 
#                                                            cities8, cities9]

cities_list = [["Kraków"]]

for cities in cities_list
    for ct in cities
        data = "../data"
        city = ct
        admin_level = "asd6"
        search_area = 1000
        attr = :education
        wilderness_distance = 300
        shape = "rectangle"
        calculate_percent = true
        num_of_points = 360
        distance_sectors = 200.0
        scrape_config = "../poi_config_test.csv"
        city_sector = prepare_city_map(
                    city, #city_name
                    admin_level, #admin_level
                    search_area, #search_area
                    wilderness_distance, #wilderness_distance
                    shape; #shape
                    calculate_percent = true,
                    num_of_points = num_of_points,
                    scrape_config = scrape_config,
                    dir=data)

        dir_in = "../data"
        road_types = ["motorway", "trunk", "primary", "secondary", 
                    "tertiary", "residential", "service", "living_street", 
                    "motorway_link", "trunk_link", "primary_link", "secondary_link", 
                    "tertiary_link"] 
        osm_file = "$city.osm"
        #graph_file_name = "Warszawa_graph.csv"
        #node_file_name = "Warszawa_nodes.json"
        dir_in=dir_in
        parsed = OpenStreetMapX.parseOSM(string(dir_in,"/",osm_file))
        ways = parsed.ways
        filtered_ways = OSMXGraph.filter_ways(ways,road_types)
        roads_all, road_tags, nds_all = OSMXGraph.find_all_points(filtered_ways, parsed)
        edges = OSMXGraph.ways_to_edges(roads_all,road_tags,parsed,nds_all)
        df = OSMXGraph.edges_to_df(edges)
        sparse_index = OSMXGraph.create_sparse_index(df.from_id,df.to_id,df.id)
        warsaw_center = city_sector[2]
        nodes = df[:,:from_LLA]
        rslts, center_kde = kernel_density_roads(city_sector,nodes)
        rs = vec(rslts)
        percentiles[city] = mean(center_kde .>= rs)
    end
end

println(percentiles)