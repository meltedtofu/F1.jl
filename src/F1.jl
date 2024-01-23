module F1

using DataFrames, CSV, GMT, IterTools, Distances, Plots, TravellingSalesman

function load_all()
    out = Dict()
    for f in readdir(joinpath(@__DIR__, "..", "data"); join=true) |> Base.Fix1(filter, p -> endswith(p, "csv"))
        out[Symbol(chopsuffix(basename(f), ".csv"))] = DataFrame(CSV.File(f))
    end
    out
end

function circuits_for_season(data, year::Int)
    innerjoin(filter(:year => y -> y == year, data[:races]),
              data[:circuits],
              on = :circuitId;
              makeunique=true) |> Base.Fix2(sort, [:round])
end

function totaldist(circuits)
    (IterTools.partition(circuits, 2, 1) .|> part -> Distances.haversine(part...)) |> sum
end

function season_distance(data, year::Int)
    circuits_for_season(data, year)[!, ["lng", "lat"]] |>
        eachrow |>
        totaldist
end

function plot_circuits(actual, shortest, outpath)
    coast(region=:g, proj=(name=:cylindricalStereographic, center=(0,45)), land=:seashell4, shore=:black, ocean=:cornsilk, area=5_000)
    GMT.scatter!(actual[!, "lng"], actual[!, "lat"])
    GMT.plot!(actual[!, "lng"], actual[!, "lat"])

    IterTools.partition(shortest, 2, 1) .|>
        edge -> GMT.plot!([first(edge)["lng"], last(edge)["lng"]],
                          [first(edge)["lat"], last(edge)["lat"]],
                          pen=:red)

    GMT.plot!([0], [0], savefig=outpath) # Degenerate plot! to save the figure. If someone finds an obvious save method please replace this
end

function plot_circuit_stats_for_all_seasons(rawdata, shortestpaths, outdir)
    # Bar chart showing distance for seasons
    distances = rawdata[:seasons][!, "year"] .|> year -> (year, season_distance(rawdata, year))
    shortestdistances = rawdata[:seasons][!, "year"] .|> (year -> (year, map(circuit -> [circuit["lng"], circuit["lat"]], shortestpaths[year]) |> totaldist))
    Plots.bar(first.(distances), last.(distances)./1_000, ylabel="km", label="actual")
    Plots.bar!(first.(shortestdistances), last.(shortestdistances)./1_000, label="shortest")
    imagepath = joinpath(outdir, "distances.png")
    savefig(imagepath)

    (imagepath,)
end

function makecleandir(d)
    isdir(d) && rm(d, recursive=true)
    mkpath(d)
end

function makedirs()
    baseout = joinpath(@__DIR__, "..", "rendered")
    mapout = joinpath(baseout, "maps")
    statsout = joinpath(baseout, "stats")

    makecleandir(mapout)
    makecleandir(statsout)

    (mapout, statsout)
end

function dothething()
    rawdata = load_all()
    (mapout, statsout) = makedirs()

    actualpaths = Dict()
    shortestpaths = Dict()
    for year ∈ rawdata[:seasons][!, "year"]
        actual = circuits_for_season(rawdata, year)
        shortest = actual |> TravellingSalesman.build_tsp_model_for_season |> TravellingSalesman.solve!

        actualpaths[year] = actual
        shortestpaths[year] = shortest

        plot_circuits(actual, shortest, joinpath(mapout, "calendar-$(year).png"))
    end

    plot_circuit_stats_for_all_seasons(rawdata, shortestpaths, statsout)
end

export dothething

end # module F1
