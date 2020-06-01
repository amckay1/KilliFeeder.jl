# NOTE: this requires installation of python qr code assistance: https://pypi.org/project/qrcode/
function flashesp8266(boot_image, baudrate, port)
    run(`esptool.py --baud $baudrate --port $port erase_flash`)
    run(`esptool.py --port $port --baud $baudrate write_flash --flash_size=detect 0 $boot_image`)
end

function write2esp8266(µpython_dir, ForOrRev, OneorTwo)
    mainfile = "main.py"
    stepperfile = "stepper_fxns.mpy"
    if ForOrRev == "r"
        stepperfile = "rev_stepper_fxns.mpy"
    end
    println("writing mainfile $mainfile")
    println("adding in stepperfile $stepperfile")
    
    cmds2write = """open ttyUSB0
    lcd $µpython_dir
    put $mainfile main.py
    put $stepperfile stepper_fxns.mpy
    exec import machine
    exec ci = ubinascii.hexlify(machine.unique_id()).decode("utf-8")
    exec print(ci)
    """
    f = open("temp.mpf", "w")
    write(f, cmds2write)
    close(f)
    println(pwd())
    run(`mpfshell -s temp.mpf`)
    #clientid = read(`mpfshell -s temp.mpf`, String)
    #clientid = match(r"]> ([0-9a-z]+)\r", clientid)[1] 
    rm("temp.mpf")
    return true #clientid
end

function flashesp8266()
    baudrate = Meta.parse(KilliFeeder.conf["Feeder"]["baudrate"])
    port = KilliFeeder.conf["Feeder"]["port"]

    µpython_dir = joinpath(pwd(), "micropythoncode")
    boot_image = joinpath(pwd(), "micropythoncode", "esp8266-20180511-v1.9.4.bin")
    ForOrRev = "n"

    if !isdir("qr_out")
        mkdir("qr_out")
    end
    println("Flashing $boot_image onto esp8266, is the stepper forward or reverse?")
    println("f/r")
    ForOrRev = readline()
    println("Pi3-AP1 or Pi3-AP2?")
    OneorTwo = readline()
    println("flashing for direction $ForOrRev and server $OneorTwo")

    while ForOrRev == "f" || ForOrRev == "r"
        flashesp8266(boot_image, baudrate, port)
        clientid = write2esp8266(µpython_dir, ForOrRev, OneorTwo)
           println("")
           println("client id is $clientid")
           pageout = "http://www.KilliFeeder.com:8500/$clientid"
           a = read(`qr $pageout`)
           write("qr_out/$clientid.png", a)
        println("Finished, remove device.")
        println("Ready to flash another device, is the stepper forward or reverse?")
        println("f/r")
        ForOrRev = readline()
    end
end

# this is working, just need to hook up the previous mainloop fxn
function printQRcodes()
    timestamp = Dates.datetime2unix(now())
    canv = SVG("output_$timestamp.svg", 210mm, 297mm)
    wh = [(w,h) for w in 20:22:190 for h in 20:25:240]# 210 x 297mm
    println("Would you like to delete the QR pngs? y/n")
    delqrcodes = readline()
    array = []
    for (i,p) in enumerate(readdir("qr_out"))
       widt, heigh = wh[i]
        filepath = joinpath("qr_out","$p")
        pname = split(p, ".")[1]
        rawimg = read(filepath);
        push!(array, compose(context(), text((widt+2)mm, (heigh+23)mm, pname)) )
        push!(array, compose(context(), bitmap("image/png",rawimg,(widt)mm, (heigh)mm, 20mm, 20mm)))
        if delqrcodes == "y"
            rm(filepath)
        end
    end
        
    c = compose(array...)
    draw(canv, c)
end 


#NOTE: will want this to print out id as well for better tracking
#printQRcodes()


