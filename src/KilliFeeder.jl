module KilliFeeder

using Dates, StatsBase, SQLite, DelimitedFiles, IterableTables, Plots, DataStructures, Compose, Pkg

#println("including scripts")

include("esp8266flash.jl")
include("serverfxns.jl")
include("guifxns.jl")
include("watchmanfxns.jl")

#println("loading config")

global conf = load_config()

end
