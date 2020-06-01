#ENV["GKSwstype"]="svg"

function get_dicts(time_db, feed_db)
    allids = union(unique(time_db[1][:,1]), unique(feed_db[1][:,1]))
    tdict = Dict(map(p -> p => [], allids))
    fdict = Dict(map(p -> p => [], allids))
    for i in 1:size(time_db[1])[1]
        r = time_db[1][i,:]
        push!(tdict[r[1]], r[5])
    end
    for i in 1:size(feed_db[1])[1]
        r = feed_db[1][i,:]
        push!(fdict[r[1]], (r[2:end]))
    end
    return tdict, fdict
end

function send_cal_msg(id::AbstractString)
    domain = Ft2k.conf["Watchman"]["domain"]
    run(`mosquitto_pub --cafile /etc/mosquitto/ca_certificates/ca.crt -h $domain -t deltacal -m $id,no,88 -p 8883`)
    println("sent mqtt msg to deltacal for $id")
end

function send_deltaorder_msg(id, scheme)
    domain = Ft2k.conf["Watchman"]["domain"]
    println("sending deltaorder for $id for $scheme")
    feedingtimes = [] 
    times = []
    if scheme == "7times"
        feedingtimes = [7.2 9 11 13 15 17 18.8]
    elseif scheme == "12times"
        feedingtimes = collect(7.5:1:18.5)
    elseif scheme == "manual"
        feedingtimes = [7.4 8.4 13.4 14.4]
    elseif scheme == "DR"
        feedingtimes = [7.4 7.9 8.4]
    elseif scheme == "comp7"
        feedingtimes = [7.2 7.5 7.8 8.0 8.2 8.4 8.6]
    end
    for t in feedingtimes
        push!(times, Int(round(t*60*60+2)))
    end
    times = [x+rand(-240:240) for x in times]    
    joinedtimes = join(times, ",") 
    # actual publication of feedings
    try
        run(`mosquitto_pub --cafile /etc/mosquitto/ca_certificates/ca.crt -h $domain -p 8883 -t deltaorder -m $id:$joinedtimes`)
        println("sent mqtt msg to deltaorder for $id")
        println("feedings now: $joinedtimes")
    catch
        println("ERROR: could not update commands")
    end
end
# map(p -> send_deltaorder_msg(p, "7times"), lifespancohort)

function pullfeedingcountsbyday(fdict)
    daysoi = unique(map(p -> (p[5]), fdict))
    countdict = Dict(map(p -> p[1] => p[2], [(i,0) for i in daysoi]))
    [countdict[(i[5])] += 1 for i in fdict]
    lcd = length(countdict)
    feed_day = Array{Date,1}(undef, lcd)
    feed_num =  Array{Int64,1}(undef, lcd)
    i = 1
    for (k,v) in countdict
        feed_day[i] = k
        feed_num[i] = v
        i += 1
    end
    return feed_day, feed_num
end

function setup_app_comps(tdict, fdict, allids, sqlite_db)
    charray = []
    cha_dict = Dict()
    cohort_dict = Dict("cohort1" => "cohort1", "cohort2"=> "cohort2")
    for i in 1:size(sqlite_db[1])[1]
        r = sqlite_db[1][i,:]
        id = r[1]
        if haskey(tdict, id) && length(tdict[id])>0
            feedings = r[2]
            calibrated =r[3]
            num_feedings = (length(split(feedings, ",")))
            nowtime = now(Dates.UTC)-Hour(8)
            last_checkedin = (Int(round((Dates.datetime2unix(nowtime) - maximum(tdict[id]) )/60)))
            if length(fdict[id]) > 0
                fdlookup = sort(fdict[id], by = p -> p[5], rev = true)[1]
                last_fed_diff = (fdlookup[3] - fdlookup[2])
            else
                last_fed_diff = 2000 
            end
            cha_dict[id] = feedings
            push!(charray, [id feedings calibrated num_feedings last_checkedin last_fed_diff] )
        end
    end

    charray = sort(charray, by = p -> p[6])
    return charray, cha_dict
end


function getcheckdict(charray)
    domain = Ft2k.conf["Watchman"]["domain"]
    checkdict =OrderedDict()
    for r in charray 
        id = r[1]
        checkdict[id] = hbox(
                             pad(1em,node(:div, HTML("<a href=http://$domain:8500/$id>$id</a>"))),
                             pad(1em,node(:div, string(r[4]))), # 
        pad(1em,node(:div, string(r[5]))), # 
        pad(1em, node(:div, string(r[6]))), # 
        pad(1em, node(:div, r[3])),
        pad(1em, node(:div, r[2])) # 
       )
    end
    return checkdict
end


function getfinalapp(tdict, fdict, ids, sqlite_db,apps, checkdict)
    apps = values(apps) 
    ui = vbox( # put things one on top of the other
              node(:div, "Dashboard 3000"),
              vbox(values(checkdict)...)
             )
    base_app = page("/", req -> ui)
    base_app = Mux.mux(base_app)

    appfinal = Mux.stack(base_app, apps...)
    return appfinal
end

function get_dbvalues()
    time_db, feed_db, sqlite_db = pull_configure_data(Ft2k.conf)
    tdict, fdict = get_dicts(time_db, feed_db)
    ids= union(collect(keys(tdict)),collect(keys(fdict)), unique(sqlite_db[1][:,1]))
    return tdict, fdict, ids, sqlite_db
end

# goal here is to load labels from csv file
function load_labels()
    labelsbackup = joinpath(pwd(), "data", "labelsbackup.csv")
    # load csv file, create if not there already
    if !isfile(labelsbackup)
        writedlm(labelsbackup, ["feeder" "label"],',')  
    else
        labels = readdlm(labelsbackup, ',') 
    end

    # parse into dict
    labels = Dict(zip(labels[:,1], labels[:,2]))

    # return Dict
    return labels
end

# goal here is to backup labels to csv file, overwriting
function backup_labels(labels)
    labelsbackup = joinpath(pwd(), "data", "labelsbackup.csv")
    writedlm(labelsbackup, labels, ',')
end

#=
function set_label(id, label, labels)

println("Label for $id set to $label")
end
=#


function update_plots(fdicto, ido)
    id = ido[]
    p11 = Array{Any,1}()
    p12 = Array{Any,1}()
    p21 = Array{Any,1}()
    p22 = Array{Any,1}()
    p31 = Array{Any,1}()
    p32 = Array{Any,1}()
    if !haskey(fdicto[], id)
        println("No $id in fdict")
    end
    feed_day, feed_num= pullfeedingcountsbyday(fdicto[][ido[]])
    sortedfeed = sortslices(hcat(feed_day, feed_num), dims = 1)
    println(sortedfeed)

    if length(fdicto[][id])> 50
        p11 = collect(1:50)
        p12 = map(p-> p[3]-p[2], fdicto[][id][end-49:end])
        p21 = map(p -> p[6],fdicto[][id][end-49:end])
        p22 = map(p -> p[3]-p[2], fdicto[][id][end-49:end])
        p31 = sortedfeed[:,1] # hcat(sortedfeed[:,1], sortedfeed[:,2])
        p32 = sortedfeed[:,2] # hcat(sortedfeed[:,1], sortedfeed[:,2])
    elseif length(fdicto[][id])< 2 
        p11 = "No feedings"
        p21 = "No feedings"
        p31 = "No feedings"
        p12 = "No feedings"
        p22 = "No feedings"
        p32 = "No feedings"
    else
        ll = length(fdicto[][id])
        p11 = collect(1:ll)
        p21 = map(p -> p[6],fdicto[][id])
        p31 = sortedfeed[:,1] #hcat(sortedfeed[:,1], sortedfeed[:,2])
        p12 = map(p-> p[3]-p[2], fdicto[][id])
        p22 =map(p -> p[3]-p[2], fdicto[][id])
        p32 = sortedfeed[:,2] #hcat(sortedfeed[:,1], sortedfeed[:,2])
    end
    # strictly debugging
    #map(p -> checkp(p), (p11, p12, p21, p22, p31, p32))
    return p11, p12, p21, p22, p31, p32
end

function reroute(p, domain, ido)
    println("Testing")
    println(p)
    ido[] = p
    # labelchooser[] = labelso[ido[]] 
    #    labelmaker = textbox(hint= "Create New Label"; value = "")
    println(domain)
    node(:div, HTML("<head> <meta http-equiv=\"refresh\" content=\"1; URL=http://$domain:8500/\"/> </head>"))
    #  node(:div,"<h1>Hi!</h1>")
    #   respond("<h1>Hi!</h1>")
    #,respond("<head> <meta http-equiv=\"refresh\" content=\"0; URL=http://localhost:8500/\"/> </head>"
end



# this will not update, need an immutable app structure that allows new units to be added
# This is the main loop for restarting the static pages every 10 min
function ml()
    ENV["GKSwstype"]="svg"

    tdict, fdict, ids, sqlite_db = get_dbvalues()
    #host = Ft2k.conf["Watchman"]["domain"]
    ids = convert(Array{String}, ids)

    # TODO remove for debug
    #ids = ids[1:1]
    ido = Observable(ids[1])

    # this loads any previously saved labels/metadata
    labels = load_labels()

    # make values observables
    tdicto = Observable(tdict)
    fdicto = Observable(fdict)
    idso = Observable(ids)
    sqlite_dbo = Observable(sqlite_db)
    labelso = Observable(labels)

    # setup feeding scheme:
    feedingscheme = sqlite_dbo[][1][findfirst(p -> p == ido[], sqlite_dbo[][1][:,1]), 2]
    feedingscheme = Observable(feedingscheme)
    on(sqlite_dbo) do p
        feedingscheme[] = sqlite_dbo[][1][findfirst(p -> p == ido[], sqlite_dbo[][1][:,1]), 2]  
    end
    feedschemetext = pad(1em, feedingscheme)

    # check boxes
    toggledfeeders = Observable(Dict(map(i -> i => true, ids)))
    toggledfeeder = checkboxes(Dict("Enrolled?" => true))
    on(p -> toggledfeeders[ido[]] = !toggledfeeders[ido[]], toggledfeeder)
    #
    # this loads any previously saved labels/metadata
    labels =load_labels()
    labelso = Observable(labels)
    labelslist = Observable(unique(values(labelso[])))# Observable(["", "LifespanCohort1"])

    labelmaker = textbox(value = "")
    submit_button = button("Make New Label")

    on(submit_button) do p
        push!(labelslist[], labelmaker[])
        # x = unique(values(labelso[]))
        # labelslist[] = x
        labelslist[] = labelslist[]
    end

    # setup labels
    if !haskey(labelso[], ido[])
        labelso[][ido[]] = "no label"
    end

    # dropdown input
    textlabel = Observable(labelso[][ido[]])
    labelchooser = dropdown(labelslist) 
    on(labelchooser) do p
        println("labelchoooser chooses $p")
        labelso[][ido[]] = p
        textlabel[] = p
    end

    # need to get calibration value here TODO
    calibrated = Observable("no")
    calibratedtext = pad(2em, calibrated)

    # calibrate button 
    calibrate_button = button("Calibrate")
    on(calibrate_button) do p
        calibrated[] = "yes"
        send_cal_msg(ido[])
    end

    # debug 7
    debug_box_7 = button("Set orders for 7 times")
    on(n -> send_deltaorder_msg(ido[], "7times"), debug_box_7)
    # debug 12
    debug_box_12 = button("Set orders for 12 times")
    on(n -> send_deltaorder_msg(ido[], "12times"), debug_box_12)
    # debug manual
    debug_box_manual = button("Set orders for manual")
    on(n -> send_deltaorder_msg(ido[], "manual"), debug_box_manual)
    # debug DR
    debug_box_DR = button("Set orders for DR")
    on(n -> send_deltaorder_msg(ido[], "DR"), debug_box_DR)
    # debug compressed 7
    debug_box_comp7 =button("Set orders for Compressed7")
    on(n -> send_deltaorder_msg(ido[], "comp7"), debug_box_comp7)

    # plots 
    #    p11, p12, p21, p22, p31, p32 = Ft2k.setupplots(fdicto, ido[])  
    p11 ="" 
    p12 = ""
    p21 = ""
    p22 =""
    p31 =""
    p32 =""
    p11, p12, p21, p22, p31, p32= update_plots(fdicto, ido) # , p31, p32 

    println("plotting plots")
    plt1 = Observable(plot());
    plt2 = Observable(scatter()); # scatter
    plt3 = Observable(bar());
    
    #plt1 = Observable(plot(p11, p12, legend = false, ylim = (-10, 1024)));
    #plt2 = Observable(scatter(p21, p22, legend = false, ylim = (-10, 1024))); # scatter
    #plt1 = Interact.@map plot(&p11, &p12, legend = false, ylim=(-10,1024));
    #plt2 = Interact.@map scatter(&p21, &p22, legend = false, ylim = (-10, 1024)); # scatter
    #plt3 = Interact.@map plot(&p31, &p32, legend = false, ylim = (0, 15));
    
    on(ido) do p
        println("trying to update plots")
        # strictly debugging
        #map(p -> checkpo(p), (p11, p12, p21, p22, p31, p32))
        p1, p2, p3, p4, p5, p6 = update_plots(fdicto, ido) #, p5, p6 
        plt1[] = plot(p1, p2, legend = false, ylim = (-10, 1024));
        plt2[] = scatter(p3, p4, legend = false, ylim = (-10, 1024));
        plt3[] = bar(p5, p6, ylim = (0, 16));
        plt3[] = vline!([p5[end]])
        feedingscheme[] = sqlite_dbo[][1][findfirst(p -> p == ido[], sqlite_dbo[][1][:,1]), 2]  
    #    labelmaker = textbox(hint= "Create New Label"; value = "")
    end

    textout = pad(2em, textlabel)
    plt1out = pad(1em, plt1)
    plt2out = pad(1em, plt2)
    plt3out = pad(1em, plt3)
    labelmakerpad = pad(1em, labelmaker)
    submitpad = pad(1em, submit_button)
    labelchooserpad = pad(1em, labelchooser)

    # would be good to have colors on these debug boxes to distinguish them
    pageui = hbox(
                  vbox(pad(1em, ido),calibratedtext, feedschemetext,
                       hbox(toggledfeeder, 
                            textout,
                            labelchooserpad, labelmakerpad, submitpad),
                       plt1out, plt2out, plt3out),#, plt3
                  vbox(pad(2em, calibrate_button), 
                       pad(2em, debug_box_7), 
                       pad(2em, debug_box_12), 
                       pad(2em, debug_box_manual),
                       pad(2em, debug_box_DR),
                       pad(2em, debug_box_comp7),
                      ))

    rerouting_apps  = []
    for p in ids
        test=page("/$p", req->reroute(p, "www.ft2k.com", ido))#respond("<h1>Hi!</h1>")) #
        push!(rerouting_apps, test)
    end

    p2 = pad(1em, ido) 

    base_app = page("/", req -> pageui)
    overview_app = page("/all", req -> p2)
    appfinal = Mux.stack(base_app, overview_app, rerouting_apps...)

    # this updates feeding values, but only every 60 seconds, need to make a function?
    logged = [] 
   #@async while true
   @async while true
        sleep(120)
        tdict, fdict, ids, sqlite_db = get_dbvalues()
        println("just updated fdict and co")
        ids = convert(Array{String}, ids)

        # update all observables somehow, this seems off
        fdicto[] = fdict
        tdicto[] = tdict
        idso[] = ids
        sqlite_dbo[] = sqlite_db

        # email check
        feedersDown = check_man_down(tdicto[])

        # check whether any feedings have been missed outside given window
        missedfeedings =check_missed_feedings(fdicto[], sqlite_dbo[])
        
        # Email out as needed
        logged = Ft2k.checkAndEmail(logged, feedersDown, missedfeedings)

        # backup labels
        println("backing up labels")
        println(labels)
        backup_labels(labels)
        GC.gc()
        println("restarting async loop")
    end

    host = "0.0.0.0"
    serving = WebIO.webio_serve(appfinal, host, 8500) 
end

function debug_deltaorder(id, secondsfromnow, interval, numberoffeedings)
    domain = Ft2k.conf["Watchman"]["domain"]
    nowtime = Dates.Time(Dates.now() - Hour(7))
    # currently set for PST day light savings
    nowtime = Hour(nowtime).value * 60*60 + Minute(nowtime).value * 60 + Second(nowtime).value #- 7*60*60
    println(nowtime)

    feedingtimes = [t for t in (nowtime + 60):interval:(nowtime+120*numberoffeedings)] 
    joinedtimes = join(feedingtimes, ",") 
    try
        run(`mosquitto_pub --cafile /etc/mosquitto/ca_certificates/ca.crt -h $domain -p 8883 -t deltaorder -m $id:$joinedtimes`)
        println("sent mqtt msg to deltaorder for $id")
        println("feedings now: $joinedtimes")
    catch
        println("ERROR: could not update commands")
    end
end
