using Luxor
using PythonCall
using Colors
using OpenStreetMapXPlot
using Plots
using DataFrames


function plot_heatmap(city_points, attr_points,boundaries,
                        attribute, city, points_in_sector,
                        search_area,
                        wilderness_distance)
    
    north = [i.north for i in city_points]
    east = [i.east for i in city_points]
    figure = Plots.scatter(east,north,zcolor = attr_points,legend=false,
                    colorbar=true, aspect_ratio=:equal, color = :oslo,
                    title = string("city: ", city,
                    " attribute: ", attribute,"\n",
                    " points_in_sector: ", points_in_sector,"\n",
                    " search area: ", search_area,"\n",
                    " wilderness_distance: ", wilderness_distance,"\n"),
                    titlefontsize=10,
                    fmt = :svg,
                    zscale = :log10)

    grouped_ways = DataFrames.groupby(boundaries, :wayid)
    for (key, way) in pairs(grouped_ways)
        Plots.plot!(figure, way.x, way.y, label="wayid $(key)", 
                                        line=:path,legend=false,linecolor=:red,
                                        linewidth=2)
    end
    return figure
end

function plot_attractiveness_of_sectors_abs(num_of_sectors,distance_between_sectors,
                                                cities_attr,labels,plotconfig)
    x_axis = [i*distance*distance_between_sectors for i in 1:num_of_sectors]./1000
    Plots.plot(x_axis,cities_attr, labels = labels; plotconfig...)
end

function plot_attractiveness_of_sectors_prcnt(cities_attr,labels,plotconfig)
    x_axis = [i for i in 1:100]
    Plots.plot(x_axis,cities_attr, labels = labels; plotconfig...)
end