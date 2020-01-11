### TV DB Scraper
`tvdb_scrape.sh` is a command line tool for retrieving TV show episode information from **thetvdb.com** API

## Pre-Requirements
* you must create a **thetvdb.com** account
* you must create an API key
* A UNIX operating system with awk, bc, curl, iconv, jq, sed

## Requirements
* the `tvdb_scrape.sh` script expects a variable named `defaults_file` (defaults to `"/etc/default/tvdb_scrape"`) that points to a configuration file whose format is as follows:
```
TVDB_USERNAME="<your thetvdb.com username>"
TVDB_USERKEY="<your thetvdb.com user key> (login and visit your dashboard to retrieve this)"
TVDB_APIKEY="<your thetvdb.com API key>"
TVDB_URL="https://api.thetvdb.com"
JWT_FILE="/tmp/${USER}.thetvdb_api.token"
# 86400 seconds = 24 hours
JWT_EXPIRY="3600"
incoming_folder="<path to files needing to be renamed>"
staging_folder="<path to put renamed files>"
```
  * **NOTE:** The `defaults_file` variable in the script can be overridden by exporting an environment variable called `TVDB_SCRAPE_DEFAULTS`

This script parses the named file to create something knowable by **thetvdb.com** API like so:
* Assume a path of `incoming_folder="/tmp/foo"`
* Assume a path of `staging_folder="/tmp/staging"`
* Assume a name of tvshow in `incoming_folder` of `"tvshow.name.s01e01.x264.ExAmPlE.mkv"`
* `tvdb_scrape.sh /tmp/foo/tvshow.name.s01e01.x264.ExAmPlE.mkv`
  * ... should produce output like so:
    * ```mv "/tmp/foo/tvshow.name.s01e01.x264.ExAmPlE.mkv" "/tmp/staging/TV Show Name S01E01 - Episode Name.mkv"```
  * **NOTE:** the script doesn't run the above commands to rename the file, but rather echoes out the commands to be run.  To apply what the script wants to do, rerun the script like so:
    * ```tvdb_scrape.sh /tmp/foo/tvshow.name.s01e01.x264.ExAmPlE.mkv | sh``` 
* If the tv show is located inside of a subfolder, the script will also emit commands to remove the subfolder
* If there are multiple video files in the subfolder, you can provide a second argument `batch` which will prevent the script from emitting the command to remove the subfolder
* If the second argument to the script is `debug`, `debug-batch`, `batch-debug`, `debugbatch`, or `batchdebug` then debugging output regarding retrieved series information will also be displayed in addition to the file rename/folder rm commands

