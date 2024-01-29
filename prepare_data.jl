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
