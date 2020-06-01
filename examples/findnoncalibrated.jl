using Ft2k, DelimitedFiles, Statistics



lsc = readdlm("/home/ubuntu/.ft2k/data/lifespancohort_feeders_all.csv", ',', String)

# filter to last 24 hours
nowtime  = now(Dates.UTC) - Hour(7)
todayfeedings= Dict()
for (k,v) in fdict
    todayfeedings[k] = filter(p -> p[5] == Date(nowtime), v)
end

x = filter((k,v) -> in(k, lsc), todayfeedings)

# these are somehow not showing up in fdict but should, all starting with 0...
missingids = setdiff(lsc, collect(keys(x)))

# have not yet fed
notfed = filter((k,v) -> length(v) < 1, x)

# remove these from dict
x = filter((k,v) -> !haskey(notfed, k), x)

# creating sorted list of ids with corresponding low diffs
y = []
for (k,v) in x
    push!(y, (mean(map(p -> p[3] - p[2], v)),k))
end
sort(y)








