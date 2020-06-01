using Ft2k

#cd(joinpath(ENV["HOME"], "ft2k/Software/Watchman"))
#include("utils/watchman_fxns.jl") # 5.544937 seconds on macbook

# load config file (now Ft2k.conf from global)
#configuration = load_config() # 0.14 seconds

# rsync with pi server to get most updated data, NOTE: linux specific
success = Ft2k.check_server_updating(Ft2k.conf) # 3.222670 seconds on macbook

# don't need this because wrapped in "continuouspull"
tdict, fdict, ids, sqlite_db = Ft2k.get_dbvalues()

# check whether any feeders have mysteriously fallen off the grid
feedersDown = Ft2k.check_man_down(tdict)

# check whether any feedings have been missed outside given window
missedfeedings =Ft2k.check_missed_feedings(fdict, sqlite_db)

logged = []
logged = Ft2k.checkAndEmail(logged, feedersDown, missedfeedings)
# sleep for a bit

