using Luxor
using Colors
using OpenStreetMapXPlot
using Plots
using DataFrames

function plot_heatmap(city_points, attr_points,boundaries,
                        attribute, city,
                        search_area,
                        wilderness_distance)
    
    north = [i.north for i in city_points]
    east = [i.east for i in city_points]
    figure = Plots.scatter(east,north,zcolor = attr_points,legend=false,
                    colorbar=true, aspect_ratio=:equal,
                    #markerstrokecolor = attr_points,
                    #markerstrokealpha=0.3,
                    markerstrokewidth = 0,
                    markershape=:rect,
                    markersize = 2,
                    title = string("city: ", city,
                    " attribute: ", attribute,"\n",
                    " search area: ", search_area,"\n",
                    " wilderness_distance: ", wilderness_distance,"\n"),
                    titlefontsize=10,
                    fmt = :svg)

    grouped_ways = DataFrames.groupby(boundaries, :wayid)
    for (key, way) in pairs(grouped_ways)
        Plots.plot!(figure, way.x, way.y, label="wayid $(key)", 
                                        line=:path,legend=false,linecolor=:red,
                                        linewidth=2)
    end
    return figure
end

function plot_attractiveness_of_sectors_abs(num_of_sectors,distance_between_sectors,
                                                cities_attr,labels)
    x_axis = [i*distance_between_sectors for i in 1:num_of_sectors]./1000
    Plots.plot(x_axis,cities_attr, labels = labels, marker=(:circle,2))
end

function plot_attractiveness_of_sectors_prcnt(cities_attr,labels,title)
    x_axis = [i for i in 1:100]
    Plots.plot(x_axis,cities_attr, labels = labels,marker=(:circle,2), title=title)
end

function tile_plot(boundaries, density, xs, ys, title)
    
    figure = Plots.plot()
    grouped_ways = DataFrames.groupby(boundaries, :wayid)
    for (x,y,d) in zip(eachrow(xs),eachrow(ys),density)
        Plots.plot!(figure, x, y, seriestype = :shape, lw = 0, fillalpha=1,
                    aspect_ratio=:equal, legend = false, fill_z=d)
    end
    for (key, way) in pairs(grouped_ways)
        Plots.plot!(figure, way.x, way.y, label="wayid $(key)", 
                    line=:path,legend=false,linecolor=:red,
                                        linewidth=2, title=title)
    end
    return figure
end
