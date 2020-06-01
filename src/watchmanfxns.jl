function check_server_updating(configuration)
    datadir = joinpath(ENV["HOME"], "ft2k", "Software", "Watchman", "data")
    result = readlines(`stat $datadir/ctimelog.csv`)
    tm = match(r"Modify: ([0-9/-]+ [0-9:.]+)", result[6])[1] # [0-9:.]
    dm = DateTime(split(tm," ")[1], "yyyy-mm-dd")
    tm = split(split(split(tm, " ")[2],".")[1], ":")
    tm = Meta.parse.(tm)
    timemodified = Dates.DateTime(Dates.Year(dm).value, Dates.Month(dm).value, Dates.Day(dm).value,tm[1], tm[2], tm[3])
    println("ctimelog changed last $timemodified")
    timediff = (now() - timemodified)
    println("timediff is $timediff")
    if timediff > convert(Dates.Millisecond, Dates.Minute(40)) # 20 min
        pull_success = false
        subject = "server might be down"
        msg = "ctimelog unchanged for longer than 20 min, server might be down"
        println(msg)
        email_user(subject, msg,configuration)
        return false
    end
    return true
end

function email_user(subject, msg,configuration)
    domain = Ft2k.conf["Watchman"]["domain"]
    #user_email = configuration["user_email"]
    emailcontents = 
"""EHLO $domain
AUTH LOGIN
QUtJQUk0Nlg0TFVBNjNOSjI2VFE=
QW16eHpHc2MxUnRyYm9VbVFPN1EwUUQrOGJNQWxYT3FSWG5WWnRINHFlNmk=
MAIL FROM: ft2k.sysmon@gmail.com
RCPT TO: andrew.s.mckay@gmail.com
DATA
From: ft2k.sysmon@gmail.com
To: andrew.s.mckay@gmail.com
Subject: $subject

$msg
.
QUIT"""
    f = open("mail_out_watchman.txt","w")

        write(f,emailcontents )

    close(f)
    A = `openssl s_client -crlf -quiet -starttls smtp -connect email-smtp.us-west-2.amazonaws.com:587`
    B = pipeline(A, stdin = "mail_out_watchman.txt") # /usr/sbin/ssmtp mail_out_watchman.txt
    run(B)
    #rm("mail_out_watchman.txt")
end

# pull and configure data
function pull_configure_data(configuration)
    # locating the files
    ctimefile = joinpath(ENV["HOME"],Ft2k.conf["Data"]["ctimelog"])
    cfeedfile = joinpath(ENV["HOME"],Ft2k.conf["Data"]["cfeedlog"])
    sqlitedb = joinpath(ENV["HOME"], Ft2k.conf["Data"]["dbsqlite"])

    #datafolder = joinpath(pwd(), "data")
    # loading time_db
    time_db = Array{Any,1}(undef,2)
    time_db[1] = readdlm(ctimefile, header = false,',')
    time_db[1] = time_db[1][:,1:4]
    x = [time_db[1][i,3]+Dates.datetime2unix(DateTime(time_db[1][i,4])) for i in 1:size(time_db[1])[1]]
    time_db[1] = hcat(time_db[1], x)
    time_db[1][:,1] = string.(time_db[1][:,1])
    time_db[2] = ["id" "v" "sec" "date" "unixtime"]
    #time_db = loadtable(joinpath(datafolder, "ctimelog.csv"), header_exists = false, colnames = ["id" "v" "sec" "date" "na"])
    feed_db = Array{Any,1}(undef, 2)
    feed_db[1] =readdlm(cfeedfile, header = false, ',')
    feed_db[1][:,1] = string.(feed_db[1][:,1])
    feed_db[1] = feed_db[1][:,1:6]
    feed_db[1] = [feed_db[1][i,:] for i in 1:size(feed_db[1])[1] if feed_db[1][i,6] != "2085f78900"]
    feed_db[1] = map(p -> permutedims(p[:,:], [2,1]), feed_db[1])

    feed_db[1] = vcat(feed_db[1]...)
    feed_db[1][:,6] = Dates.Date.(feed_db[1][:,6], "yyyy-mm-dd")
    y = [feed_db[1][i,2]+Dates.datetime2unix(DateTime(feed_db[1][i,6])) for i in 1:size(feed_db[1])[1]]
    feed_db[1] = hcat(feed_db[1], y)
    feed_db[2] = ["id" "sec" "out" "back" "cal" "date"]
    #feed_db = loadtable(joinpath(datafolder, "cfeedlog.csv"), header_exists = false, colnames = ["id" "sec" "out" "back" "cal" "date"])
    #db = SQLite.DB(joinpath(ENV["HOME"], "ft2k", "Software", "Server", "db.sqlite"))
    db = SQLite.DB(sqlitedb)
    sqlite_db = Array{Any,1}(undef,2)
    sqlite_db[1] = DataFrame(SQLite.Query(db, "SELECT * FROM clients;"))
    sqlite_db[1] = convert(Array, sqlite_db[1])
    sqlite_db[2] = ["id" "feedings" "cal" "diff"]
    #sqlite_db = table(SQLite.query(db, "SELECT * FROM clients;"))
    return time_db, feed_db, sqlite_db
end

function findmaxarray(array)
    da = Dict(zip(unique(array[:,1]), zeros(size(array[:,1]))))
    for i in 1:size(array)[1]
        if da[array[i,1]] < array[i,5]
            da[array[i,1]] = array[i,5]
        end
    end
    return da
end
        
# check whether any feeders have mysteriously fallen off the grid
function check_man_down(tdict)
    max_device_sleep_sec = Meta.parse(Ft2k.conf["Watchman"]["max_sleep_time_sec"])

    #time_db2 = pushcol(time_db, :unixtime, map(p -> p.sec + Dates.datetime2unix(DateTime(p.date)), time_db))
    #most_recent = groupreduce(max, time_db2, :id, select= :unixtime)
    
    most_recent = Dict() 
    for (k,v) in tdict
        most_recent[k] = maximum(v)
    end
    nowtime = now(Dates.UTC)-Hour(7) # NOTE: this needs to change for daylight savings
    println("Now is $nowtime")
    nowtime = Dates.datetime2unix(nowtime) # needed to keep this on the right time zone
    feedersDown = []
    for (k,v) in most_recent
         if (nowtime -(2*max_device_sleep_sec)) < v < (nowtime- max_device_sleep_sec)
             push!(feedersDown, (k, v))
        end
    end
    # feedersDown = filter(p -> (nowtime-(2*max_device_sleep_sec)) < p.max < (nowtime-max_device_sleep_sec) , most_recent)
    return feedersDown
end

function get_feedings(sqlite_db, id)
    return sqlite_db[1][sqlite_db[1][:,1] .== id, :]
end

function get_last_putative_feeding(array)
    da = Dict(zip(array[:,1], array[:,2]))
    if now(Dates.UTC) - now() < Dates.Millisecond(1000)
        nowtime = now()-Dates.Hour(7)
    else
        nowtime = now()
    end
    now_sec = Dates.Second(nowtime).value + 60*Dates.Minute(nowtime).value + 60*60*Dates.Hour(nowtime).value - 20*60 # add on 20 min buffer
    
    last_feeding = Dict()
    for (k,v) in da
        feedings = Meta.parse.(split(v, ','))
        feedings = feedings[feedings .< now_sec] 
        try
            last_feeding[k] = maximum(feedings)
        catch
            last_feeding[k] = maximum(Meta.parse.(split(v, ',')))
        end
    end
    return last_feeding
end
        
# check whether any feedings have been missed outside given window
function check_missed_feedings(fdict, sqlite_db)
    # set to 120 seconds for now, in config.toml
    feeding_threshold_sec = Meta.parse(Ft2k.conf["Watchman"]["feeding_threshold_sec"])

    last_feeding = get_last_putative_feeding(sqlite_db[1]) 
    #sqlite_db2 = pushcol(sqlite_db, :most_recent_scheduled, map(p -> get_last_putative_feeding(p.orders), sqlite_db))
    nowtime  = now(Dates.UTC) - Hour(7)
    todayfeedings= Dict()
    for (k,v) in fdict
        todayfeedings[k] = filter(p -> p[5] == Date(nowtime), v)
    end
    #feed_db[1][feed_db[1][:,6] .== Date(nowtime),:]
    mostrecent_feeding = Dict()
    for (k,v) in todayfeedings
        if length(v) > 0
            mostrecent_feeding[k] = maximum(v)
        end
    end

    missedfeedings = []
    for (k,v) in last_feeding # the last putative feeding
        if haskey(mostrecent_feeding, k) && ((60*10)> (v - mostrecent_feeding[k][1]) > feeding_threshold_sec)
           # println(k, " ", v, " ", mostrecent_feeding[k][1], " ", ((60*10)+ v - mostrecent_feeding[k][1]))
            push!(missedfeedings, (k, v, Date(nowtime)))
        end
    end

   return missedfeedings
end

function checkAndEmail(logged, feedersdown, missedfeedings)
    # log both
    formail = []
    for m in missedfeedings
        if !in(m, logged)
           # read, write, create, append
            mm = join(m, ",")
            f = open("logs/feedingsmissed", "a+")
            write(f, mm)
            close(f)
            push!(formail, m)
            push!(logged, m)
        end
    end
    # email remaining
    if length(formail) > 0
        mout = join([p[1] for p in formail], ",")
        msg = "Feedings were missed for $mout"
        subject = "Missed feedings"
        email_user(subject, msg,configuration)
    end
     
    formail = []
    for m in feedersdown
        # read, write, create, append
        f = open("logs/feedersdown", "a+")
        write(f, join(m, ","))
        close(f)
        push!(formail, m)
        push!(logged, m)
    end
    if length(formail) > 0
        mout = join([p[1] for p in formail], ",")
        msg = "Feeders have not checked in: $mout"
        subject = "Dropped feeders"
        email_user(subject, msg,configuration)
    end
    return logged
end

function dailycheck(tdict, fdict, ids, sqlite_db)
    todayis = Date(now()-Hour(7))
    unixtoday = Dates.datetime2unix(DateTime(todayis))

    # filter out non-feeders
    #fdict = filter((k,v) -> length(v) > 5, fdict)

    # filter dictionaries to only have today's values
    for (k,v) in tdict
        tdict[k] = filter(p -> p > unixtoday, v) 
    end

    for (k,v) in fdict
        fdict[k] = filter(p -> p[6] > unixtoday, v)
    end

    # checked in over last day
    tdict = filter((k,v) -> length(v) > 0, tdict)
    fdict = filter((k,v) -> length(v) > 0, fdict)

    # number of check ins?
    
    # number of putative feedings over last day
    putative_feed = Dict(zip(sqlite_db[1][:,1] , length.(split.(sqlite_db[1][:,2],','))))

    outa = Array{Any}[]

    println(length(fdict))
    println(length(tdict))
    println(length(putative_feed))
    for (k,v) in tdict
        differencev = minimum(map(p -> p[3] - p[2], fdict[k]))
        push!(outa, [k length(v) length(fdict[k]) (putative_feed[k]) (length(fdict[k]) - putative_feed[k]) differencev])
    end

    outa = vcat(outa...)

    outa = outa[sortperm(outa[:,5]), :]

    subject = "Daily Check"
    msg= DataFrame(outa)
    #names!(msg, Dict(:x1 => :id, :x2 => :check_ins, :x3 => :feedingstoday, :x4 => :putative_feedings, :x5 => :feeding_diff, :x6 => :measured_diff))
    email_user(subject, msg,Ft2k.conf)
end

