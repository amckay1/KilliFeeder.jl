using Ft2k

# this is from watchmanfxns.jl 
success = Ft2k.check_server_updating(Ft2k.conf) # 3.222670 seconds on macbook

tdict, fdict, ids, sqlite_db = Ft2k.get_dbvalues()

# create summary for the day to go out after 9

Ft2k.dailycheck(tdict, fdict, ids, sqlite_db)

# to get assigned feedings from sqlite_db:
# id = "f2b00d00"
# sqlite_db[1][sqlite_db[1][:,1] .== id, :]
