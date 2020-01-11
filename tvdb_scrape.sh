#!/bin/bash
#set -x

PATH="/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin"
TERM="vt100"
export PATH TERM

SUCCESS=0
ERROR=1

let exit_code=${SUCCESS}

batch="false"
debug=""

if [ ! -z "${TVDB_SCRAPE_DEFAULTS}" ]; then
    defaults_file="${TVDB_SCRAPE_DEFAULTS}"
else
    defaults_file="/etc/default/tvdb_scrape" 
fi

if [ -e "${defaults_file}" ]; then
    . ${defaults_file}
else
    echo "    ERROR: No defaults file found at '${defaults_file}'"
    exit 1
fi

TOKEN_GEN_COMMAND="curl -L -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '{\"apikey\":\"${TVDB_APIKEY}\",\"username\":\"${TVDB_USERNAME}\",\"userkey\":\"${TVDB_USERKEY}\"}' ${TVDB_URL}/login -s | jq \".token\" | sed -e 's|\"||g'"

# Compute the date in epoch seconds
let right_now=$(date +%s)

# If there is no existing token file then generate one
# If one exists, check the expiry and generate a new one if it is too old
if [ ! -e "${JWT_TOKEN_FILE}" ]; then
    jwt_token=$(eval ${TOKEN_GEN_COMMAND})
    echo "${right_now}:${jwt_token}" > "${JWT_TOKEN_FILE}"
else
    let jwt_token_expiry=$(awk -F':' '{print $1}' "${JWT_TOKEN_FILE}")
    jwt_token=$(awk -F':' '{print $NF}' "${JWT_TOKEN_FILE}")
    
    let delta_t=$(echo "${right_now}-${jwt_token_expiry}" | bc)
    
    if [ ${delta_t} -gt ${JWT_TOKEN_EXPIRY} -o -z "${jwt_token}" ]; then
        jwt_token=$(eval ${TOKEN_GEN_COMMAND})
        echo "${right_now}:${jwt_token}" > "${JWT_TOKEN_FILE}"
    fi

fi

# See if we were passed some ancillary arguments
if [ ! -z "${2}" ]; then

    case ${2} in
    
        debug)
            debug="echo"
        ;;
    
        batch)
            batch="true"
        ;;
    
        debug-batch|batch-debug|debugbatch|batchdebug)
            debug="echo"
            batch="true"
        ;;
    
    esac

fi

# Get our JWT_TOKEN from JWT_TOKEN_FILE
JWT_TOKEN=$(awk -F':' '{print $NF}' "${JWT_TOKEN_FILE}")

# Make sure we have an input argument AND a jwt_token
if [ ! -z "${1}" -a ! -z "${JWT_TOKEN}" ]; then
    input_file_name="${1}"
    input_file=$(basename "${input_file_name}")
    input_dir=$(dirname "$(realpath -e "${input_file_name}" 2> /dev/null)" 2> /dev/null)
    file_extension=$(echo "${input_file_name}" | awk -F'.' '{print $NF}')
    series_search_regex=$(echo "${input_file}" | awk -F'[Ss][0-9][0-9][Ee][0-9][0-9]' '{print $1}' | sed -e 's|[^a-zA-Z0-9\-]| |g' -e 's| $||g' -e 's| |%20|g')

    # The last part of this variable definition is a hack for Agents of S.H.I.E.L.D.
    computed_series_slug=$(echo "${series_search_regex}" | tr '[A-Z]' '[a-z]' | sed -e 's|%20|-|g' -e 's|agents-of-s-h-i-e-l-d|agents-of-shield|g')

    ${debug} "Computed Series Slug: ${computed_series_slug}" 2> /dev/null

    jq_command="jq '.data[] | select(.slug==\"${computed_series_slug}\")'"
    eval "series_info=\$(curl -L -X GET --header 'Accept: application/json' --header \"Authorization: Bearer ${JWT_TOKEN}\" \"https://api.thetvdb.com/search/series?slug=${computed_series_slug}\" -s | ${jq_command} 2> /dev/null)"

    # If we didn't define ${series_info} then we exit quietly
    if [ ! -z "${series_info}" ]; then
        series_id=$(echo "${series_info}" | jq ".id" | sed -e 's|"||g')
	series_name=$(echo "${series_info}" | jq ".seriesName" | iconv -f utf-8 -t ascii//TRANSLIT | sed -e 's|\"||g' -e 's|:| -|g')

        ${debug} "Series ID: ${series_id}" 2> /dev/null
        ${debug} "Series Name: ${series_name}" 2> /dev/null

        episode=$(echo "${input_file}" | sed 's|^.*\([Ss][0-9][0-9][Ee][0-9][0-9]\).*$|\1|g' | tr '[a-z]' '[A-Z]')

        if [ ! -z "${episode}" ]; then
            aired_season=$(echo "${episode}" | awk -F'E' '{print $1}' | sed -e 's|^S||g')
            aired_episode=$(echo "${episode}" | awk -F'E' '{print $2}')
            episode_info=$(curl -L -X GET --header 'Accept: application/json' --header "Authorization: Bearer ${JWT_TOKEN}" "https://api.thetvdb.com/series/${series_id}/episodes/query?airedSeason=${aired_season}&airedEpisode=${aired_episode}" -s | jq ".")

            if [ ! -z "${episode_info}" ]; then
                episode_name=$(echo "${episode_info}" | jq ".data[0].episodeName" | iconv -f utf-8 -t ascii//TRANSLIT | sed -e 's|"||g' -e 's|:| -|g' -e 's|?| |g' -e 's|  | |g' -e 's| ,|,|g' -e 's| $||g')

                # Generate shell code for relocation and cleanup, provided that ${series_name} and ${episode_name} are defined
		if [ "${series_name}" != "null" -a "${episode_name}" != "null" ]; then
                    echo "mv \"${input_dir}/${input_file}\" \"${staging_folder}/${series_name} S${aired_season}E${aired_episode} - ${episode_name}.${file_extension}\""

		    if [ "${input_dir}" != "." -a "${input_dir}" != "${incoming_folder}" -a "${input_dir}" != "/" -a "${input_dir}" != "/tmp" -a "${batch}" != "true" ]; then
                        echo "rm -rf \"${input_dir}\""
                    fi

		else
	            echo "**** ERROR:  Input file '${input_file_name}' yielded a series name of '${series_name}' and episode name of '${episode_name}'" >&2
		fi

            fi

        fi

    fi

fi

exit 0

# Series info
#curl -L -X GET --header 'Accept: application/json' --header "Authorization: Bearer ${JWT_TOKEN}" 'https://api.thetvdb.com/search/series?name=blindspot' | jq "."

# Series specific episode info:
#curl -L -X GET --header 'Accept: application/json' --header 'Authorization: Bearer ${JWT_TOKEN}' 'https://api.thetvdb.com/series/295647/episodes/query?airedSeason=1&airedEpisode=1'

# Parsing episode name
#echo "star.wars.resistance.s01e12.720p.web.x264-tbs[eztv].mkv" | awk -F'[Ss][0-9]*[Ee][0-9]*' '{print $1}' | sed -e 's|[^a-zA-Z\-]| |g' -e 's| |%20|g'

# Parsing episode number
#echo "Vikings.S05E18.1080p.WEB.H264-METCON.mkv" | sed 's|^.*\([Ss][0-9]*[Ee][0-9]*\).*$|\1|g' | tr '[a-z]' '[A-Z]'
