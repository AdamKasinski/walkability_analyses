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