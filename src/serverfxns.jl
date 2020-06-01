# "ctrl_fxns"
function count_thresh(array, thresholdcount)
    returnarray = []
    count_dict = Dict(collect(zip(array, zeros(size(array)))))
    for a in array
        count_dict[a] +=1
    end
    for (k,v) in count_dict
        if v >= thresholdcount
            push!(returnarray,k)
        end
    end
    return returnarray
end
# newlifespanfeeders = count_thresh(ar, 2)

function process_raw_output(x)
    ar = []
    for y in split(x)
        push!(ar, split(y, ",")[1])
    end
    return ar
end

function when_last_checkedin(feederarray, numberoflines2check)
    tailend = readlines(`tail -$numberoflines2check mqtt/ctimelog.csv`)
    array = []
    for x in tailend
        y = split(x, ",")
        absolutetime = parse(y[3]) + Dates.datetime2unix(DateTime(Date(y[4])))
        push!(array, [y[1] absolutetime])
    end
    array = vcat(array...)
    for feeder in feederarray
        array = array[find(array[:,1] .== feeder),:] # within time window
        if length(array) < 1
            println("Feeder $feeder not found")
            continue
        end
        println("Feeder $feeder's last checkin:")
        println(Dates.unix2datetime(maximum(array[:,2])))
    end
end
# when_last_checkedin(["148c1d00" "ef901d00" "f8921d00"],10000)


# creating lifespan commands for entering into bash of RPi3 hub

# mosquitto_pub -t deltacal -m 30aea43912b4,no,88
function debug_cal(ids)
  for id in ids
    #id_times = times+rand(range, length(times))
    run(`mosquitto_pub -t deltacal -m $id,no,88`)
    println("Setting $id for calibration next check in")
  end
end

function get_feeding_regimes()
    times7 = []
    for (i,t) in enumerate([7 9 11 13 15 17 19])
        push!(times7, t*60*60+2)
    end
    times7[end] = times7[end] - (4*60)

    times12 = []
    for (t) in 7.5:1:18.5
        push!(times12, Int(round(t*60*60+30)))
    end

    times24 = []
    for (t) in 7.5:0.46:18.5
        push!(times24, Int(round(t*60*60+30)))
    end

    morning_feed = []
    for t in 7.5:1:13
        push!(morning_feed,Int(round(t*60*60)))
    end

    evening_feed = []
    for t in 13.5:1:19
        push!(evening_feed, Int(round(t*60*60)))
    end

    one_last_feed = [Int(round(18.2*60*60))]
    return Dict("times7" => times7, "times12" => times12, "morning_feed" => morning_feed, "evening_feed" => evening_feed, "one_last_feed" => one_last_feed, "times24" => times24)
end

function tosecond(datetime)
    secondsout = Dates.Second(datetime)
    secondsout += Dates.Second(Dates.Minute(datetime))
    secondsout += Dates.Second(Dates.Hour(datetime))
    return Dates.value(secondsout)
end

function getfeedingtimesFromNow(sec_interval, numberfeedings)
    debugtimes = []
    nowsec = tosecond(now())
    for (t) in (nowsec+sec_interval):sec_interval:(nowsec+(sec_interval*numberfeedings))
        println(t)
        push!(debugtimes, t)
    end
    return debugtimes
end
# getfeedingtimesFromNow(90, 10)

function getfeedingtimesFromNow(sec_interval, numberfeedings, nowinSec)
    debugtimes = []
    nowsec = nowinSec
    for (t) in (nowsec+sec_interval):sec_interval:(nowsec+(sec_interval*numberfeedings))
        println(t)
        push!(debugtimes, t)
    end
    return debugtimes
end
# getfeedingtimesFromNow(90, 10)

function debug_commands_plusRand(ids, times)
    #array = []
  for id in ids
    #id_times = times+rand(range, length(times))
    times = [x+rand(-60:60) for x in times]
    joinedtimes = join(times, ",")
    run(`mosquitto_pub -t deltaorder -m $id:$joinedtimes`)
    #push!(array, cmdout)
    println("changed orders for $id to $joinedtimes")
  end
  #return array
end
#  x = debug_commands_plusRand(checked_in_feeders, truncated)

function debug_commands(ids, times)
  for id in ids
    #id_times = times+rand(range, length(times))
    times = [x for x in times]
    joinedtimes = join(times, ",")
    run(`mosquitto_pub -t deltaorder -m $id:$joinedtimes`)
    #push!(array, cmdout)
    println("changed orders for $id to $joinedtimes")
  end
end

function get_checked_feeders(timeInterval, repeats, filelocale::AbstractString)
    #timewindow = (tosecond(now())- timeInterval) # in seconds
    timewindow = timeInterval
    tailend = readlines(`tail -500 $filelocale`)
    array = []
    for x in tailend
        y = split(x, ",")
        push!(array, [y[1] Meta.parse(y[3])])
    end
    array = vcat(array...)
    array = array[findall(array[:,2] .> timewindow),:] # within time window
    checked_in_feeders = count_thresh(array[:,1], repeats)
    return checked_in_feeders
end
#Ft2k.get_checked_feeders(57412, 1, "/home/ubuntu/ft2k/Software/Watchman/data/ctimelog.csv")

function get_checked_feeders(timeIntervalmin, repeats)
    timewindow = (tosecond(now())- timeIntervalmin*60)
    tailend = readlines(`tail -100 mqtt/ctimelog.csv`)
    array = []
    for x in tailend
        y = split(x, ",")
        push!(array, [y[1] parse(y[3])])
    end
    array = vcat(array...)
    array = array[findall(array[:,2] .> timewindow),:] # within time window
    checked_in_feeders = count_thresh(array[:,1], repeats)
    return checked_in_feeders
end
# get_checked_feeders(100, 3)

function get_checked_feeders(starttimeInterval::DateTime, endtimeInterval::DateTime, repeats)
    timewindow = (tosecond(starttimeInterval), tosecond(endtimeInterval))# (tosecond(now())- timeIntervalmin*60)
    tailend = readlines(`tail -1000 mqtt/ctimelog.csv`)
    array = []
    for x in tailend
        y = split(x, ",")
        push!(array, [y[1] parse(y[3])])
    end
    array = vcat(array...)
    array = array[find(timewindow[1].<  array[:,2] .< timewindow[2]),:] # within time window
    checked_in_feeders = count_thresh(array[:,1], repeats)
    return checked_in_feeders
end
# starttimeInterval=  DateTime(2018,7,30,14,5)
# endtimeInterval = DateTime(2018,7,30,14,20)
# get_checked_feeders(DateTime(2018,7,30,14,10), DateTime(2018,7,30,14,20), 3)

# NOTE: this one needs using JuliaDB, SQLite, IterableTables
function get_current_regime(feederarray)
    db = SQLite.DB(joinpath(ENV["HOME"],"Software", "Server", "db.sqlite"))
    sqlite_db = table(SQLite.query(db, "SELECT * FROM clients;"))
    x = filter(p -> in(p.client_id, feederarray), sqlite_db)
    x = pushcol(x, :feedcount, map(p -> length(split((p.orders).value,",")), x))
    println(x)
end
# get_current_regime(feederarray)

# "utils.jl"
function load_config()
    diroi = joinpath(@__DIR__, "..", "config", "config.toml")
    return Pkg.TOML.parsefile(diroi) 
end


