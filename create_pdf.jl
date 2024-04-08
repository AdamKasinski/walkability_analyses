using PDFmerger: append_pdf!
include("analyse.jl")
include("prepare_data.jl")
include("plots.jl")


atr_list = [:education, :entertainment, :healthcare, :leisure, :parking,
                    :restaurants, :shopping, :transport]

list_of_cities = ["cracow", "brno", "gliwice"]
is_poi_in_csv = true
num_of_sectors = 200
distance_for_sector = 50
points_in_sector = 360
distance_to_analyse = 500
plotconfig = (marker=:circle, markersize=1)
file_name = join(list_of_cities, "_")
plot_title = join(list_of_cities, " ")

