using Downloads
using OSMToolset
using OpenStreetMapX
using Downloads
using GZip
using DataFrames
using CSV

function download_data(city::String)
    if isfile(string(city,".osm"))
        return "The file is already downloaded"
    else
        url = string("https://download.bbbike.org/osm/bbbike/",city,"/",city,".osm.gz")
        output = "file.osm.gz"
        Downloads.download(url,output)
        tname = string(city,".osm")
        GZip.open("file.osm.gz", "r") do io
            open(tname, "w") do out
                write(out, read(io))
            end
        end
        rm("file.osm.gz"; recursive=false)
    end
end

function create_map(file::String)
    return get_map_data(file,use_cache = false)
end

function save_as(file::String,save_as::String)
    if save_as != ""
        CSV.write("save_as",file)
    end
end

function get_POI(file::String,config = "", save_as::String = "")
    if file[end-2:end] == "osm"
        fl = OSMToolset.find_poi(file;config)
        save_asm(fl,save_as)
        return fl
    elseif file[end-2:end] == "csv"
        return DataFrame(CSV.File(file))
    end
end