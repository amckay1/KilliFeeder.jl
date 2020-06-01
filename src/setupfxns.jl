function flashserver()
    println("running diskutil list")
    run(`diskutil list`)
    println("Which disk would you like to format?")
    disknum = readline()
    yesno = "y"
    if Meta.parse(disknum) < 2
        println("WARNING: this might be a system disk, proceed? y/n")
        yesno = readline()
    elseif yesno == "y" && disknum == "2"
        println("unzipping tar")
        run(`tar -xzf $(ENV["HOME"])/ft2k/Software/Server/2017-07-05-raspbian-jessie.zip`)
        println("unmounting and flashing disk")
        run(`diskutil unmountDisk /dev/disk$disknum`)
        run(`dd bs=1m if=$(ENV["HOME"])/ft2k/Software/Server/setup_scripts/2017-07-05-raspbian-jessie.img of=/dev/disk$disknum conv=sync`)
        # enable uart
        sleep(1)
        f = open("/Volumes/boot/config.txt", "a")
        write(f, "enable_uart=1")
        close(f)
        run(`rm -rf $(ENV["HOME"])/ft2k/Software/Server/setup_scripts/2017-07-05-raspbian-jessie.img`)
        println("finished")
    end
end

function pulldb()
    domain = conf["Watchman"]["domain"]
	while true
		run(`/usr/bin/rsync -avze "ssh -i /home/pi/.ssh/watchman.pem" ubuntu@$domain:/home/ubuntu/ft2k/Software/Server/db.sqlite /home/pi/ft2k/Software/Server/`)
		sleep(3)
	end
end


