using Luxor
using PythonCall
using Colors
using OpenStreetMapXPlot
using Plots

folium = pyimport("folium")
cm = pyimport("branca.colormap")

function plot_heatmap(city_centre, city_points, attractiveness_points,
                        zoom_start = 14, control_scale = false)
    
    min_attr = minimum(attractiveness_points)
    max_attr = maximum(attractiveness_points)

    linear = cm.LinearColormap(["red", "yellow", "green"], 
                                            vmin=min_attr, 
                                            vmax=max_attr)

    for sector in 1:size(points_cracow)[1]
        for point in 1:size(points_cracow)[2]
            lla = LLA(points_cracow[sector,point],center_cracow) 
            lt = lla.lat
            ln = lla.lon
            flm.Circle([lt,ln],popup=sector, radius =5,
                        color=linear(cracow_attr_matrix[sector,point])).add_to(map_plot)
    
        end
    end


end