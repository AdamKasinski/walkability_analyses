using Luxor
using PythonCall
using Colors
using OpenStreetMapXPlot
using Plots
using DataFrames

#folium = pyimport("folium")
#cm = pyimport("branca.colormap")

function plot_heatmap(city_points, attr_points,boundaries)
    
    north = [i.north for i in city_points]
    east = [i.east for i in city_points]
    colorbar_ticks = [minimum(attr_points), mean(attr_points), maximum(attr_points)]
    figure = Plots.scatter(east,north,zcolor = attr_points,legend=false,
    colorbar=true, aspect_ratio=:equal, color = :oslo, zscale = :log10)

    grouped_ways = DataFrames.groupby(boundaries, :wayid)
    for (key, way) in pairs(grouped_ways)
        Plots.plot!(figure, way.x, way.y, label="wayid $(key)", 
                                        line=:path,legend=false,linecolor=:red,
                                        linewidth=2)
    end
    Plots.display(figure)
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