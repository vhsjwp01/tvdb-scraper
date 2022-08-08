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

custom_regex_file="/etc/default/tvdb_scrape_custom_regex"

# WHAT: Ensure we have a defaults file
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    # Take the value from the env var if defined
    if [ ! -z "${TVDB_SCRAPE_DEFAULTS}" ]; then
        defaults_file="${TVDB_SCRAPE_DEFAULTS}"
    else
        defaults_file="/etc/default/tvdb_scrape" 
    fi
    
    # Source it or complain
    if [ -s "${defaults_file}" ]; then
        . ${defaults_file}
    else
        err_msg="No defaults found at '${defaults_file}'"
        let exit_code=${ERROR}
    fi

fi

# WHAT: Make sure we have some needed commands
# WHY:  They get used later on
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    err_msg="Missing commands:"
    this_sed=$(unalias sed > /dev/null 2>&1 ; which sed 2> /dev/null)
    
    if [ ! -z "${this_sed}" ]; then

        for i in awk basename bc curl date dirname iconv jq mv realpath rm sed tr wc ; do
            key="my_$(echo "${i}" | "${this_sed}" -e 's|-|_|g' -e 's|:|_|g' -e 's|\.|_|g')"
            value=$(unalias "${i}" > /dev/null 2>&1 ; which "${i}" 2>/dev/null)
            let status_code=${?}

            if [ ${status_code} -ne ${SUCCESS} ]; then
                let exit_code+=${status_code}
                err_msg+=" ${i}" 
            else
                eval "${key}=${value}"
            fi

        done

    else
        err_msg="No sed found ... is this a proper UNIX system?"
        let exit_code=${ERROR}
    fi

fi

# WHAT: Make sure we retrieve and save a JWT to a time-sensitive but re-usable file
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    TOKEN_GEN_COMMAND="${my_curl} -L -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '{\"apikey\":\"${TVDB_APIKEY}\",\"username\":\"${TVDB_USERNAME}\",\"userkey\":\"${TVDB_USERKEY}\"}' ${TVDB_URL}/login -s | ${my_jq} \".token\" | ${my_sed} -e 's|\"||g'"
    
    # Compute the DATE in epoch seconds
    let right_now=$(${my_date} +%s)
    
    # If there is no existing token file then generate one
    # If one exists, check the expiry and generate a new one if it is too old
    if [ ! -e "${JWT_FILE}" ]; then
        jwt=$(eval ${TOKEN_GEN_COMMAND})
        echo "${right_now}:${jwt}" > "${JWT_FILE}"
    else
        let jwt_expiry=$(${my_awk} -F':' '{print $1}' "${JWT_FILE}")
        jwt=$(${my_awk} -F':' '{print $NF}' "${JWT_FILE}")
        
        let delta_t=$(echo "${right_now}-${jwt_expiry}" | ${my_bc})
        
        if [ ${delta_t} -gt ${JWT_EXPIRY} -o -z "${jwt}" ]; then
            jwt=$(eval ${TOKEN_GEN_COMMAND})
            echo "${right_now}:${jwt}" > "${JWT_FILE}"
        fi
    
    fi

    let token_file_element_count=$(${my_sed} -e 's|:| |g' "${JWT_FILE}" | ${my_wc} -w | ${my_awk} '{print $1}')

    if [ ${token_file_element_count} -ne 2 ]; then
        ${my_rm} -f "${JWT_FILE}"
        err_msg="Could not retrieve JWT from '${TVDB_URL}'"
        let exit_code=${ERROR}
    fi

fi
        
# WHAT: See if we were passed some ancillary arguments
# WHY:  Operations potentially depend on them
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

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

            *)
                err_msg="Unknown secondary argument '${2}'"
                let exit_code=${ERROR}
            ;;
        
        esac
    
    fi

fi

# WHAT: Get our JWT from ${JWT_FILE}
# WHY:  Cannot query ${TVDB_URL} without it
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    JWT=$(${my_awk} -F':' '{print $NF}' "${JWT_FILE}")
    
    # Make sure we have an input argument AND a jwt
    if [ ! -z "${1}" -a ! -z "${JWT}" ]; then
        input_file_name="${1}"
        input_file=$(${my_basename} "${input_file_name}")
        input_dir=$(${my_dirname} "$(${my_realpath} -e "${input_file_name}" 2> /dev/null)" 2> /dev/null)
        file_extension=$(echo "${input_file_name}" | ${my_awk} -F'.' '{print $NF}')
	series_search_regex=$(echo "${input_file}" | ${my_sed} -e 's|[^a-zA-Z0-9\-]| |g' -e 's| $||g' -e 's|\([Ss][0-9]*[Ee][0-9]*\)| \1 |g' -e 's| |%20|g' | ${my_awk} -F'%20[Ss][0-9]*[Ee][0-9]*%20' '{print $1}')
    
        # You can make this script process any custom regexes in order to accurately produce
        # a ${computed_series_slug} recognizable by thetvdb API by placing them in a file called
        # '/etc/default/tvdb_scrape_custom_regex'.  Place each sed compatible regex on a line like so:
        #
        # s|agents-of-s-h-i-e-l-d|agents-of-shield|g;
        #
        # If this custom regex file is present, then it will be processed by 'sed' using the '-f' flag
        # during discernment of the '${computed_series_slug}'
        #
        computed_series_slug=$(echo "${series_search_regex}" | ${my_tr} '[A-Z]' '[a-z]' | ${my_sed} -e 's|%20|-|g')

        if [ -e "${custom_regex_file}" ]; then
            echo "test line" | ${my_sed} -f "${custom_regex_file}" > /dev/null 2>&1

            if [ ${?} -eq 0 ]; then
                ${debug} "Processing Additional regex file: '${custom_regex_file}'" 2> /dev/null
                computed_series_slug=$(echo "${computed_series_slug}" | ${my_sed} -f "${custom_regex_file}")
            else
                ${debug} "Ignoring malformed custom regex file '${custom_regex_file}'" 2> /dev/null
            fi

        fi
    
        ${debug} "Computed Series Slug: ${computed_series_slug}" 2> /dev/null
    
        JQ_command="${my_jq} '.data[] | select(.slug==\"${computed_series_slug}\")'"
        eval "series_info=\$(${my_curl} -L -X GET --header 'Accept: application/json' --header \"Authorization: Bearer ${JWT}\" \"https://api.thetvdb.com/search/series?slug=${computed_series_slug}\" -s | ${JQ_command} 2> /dev/null)"
    
        # Bail if we don't have ${series_info}
        if [ ! -z "${series_info}" ]; then
            series_id=$(echo "${series_info}" | ${my_jq} ".id" | ${my_sed} -e 's|"||g')
            series_name=$(echo "${series_info}" | ${my_jq} ".seriesName" | ${my_iconv} -f utf-8 -t ascii//TRANSLIT | ${my_sed} -e 's|\"||g' -e 's|:| -|g')
            episode=$(echo "${input_file}" | ${my_sed} -e 's| |%20|g' -e 's|\.|%20|g' -e 's|-|%20|g' -e 's|^.*%20\([Ss][0-9]*[Ee][0-9]*\)%20.*$|\1|g' | ${my_tr} '[a-z]' '[A-Z]')
    
            ${debug} "Series ID: ${series_id}"           2> /dev/null
            ${debug} "Series Name: ${series_name}"       2> /dev/null
    
            # Bail if we don't have an episode in the format of S[0-9]*E[0-9]*
            if [ ! -z "${episode}" ]; then
                aired_season=$(echo "${episode}" | ${my_awk} -F'E' '{print $1}' | ${my_sed} -e 's|^S||g')
                aired_season_numeral=$(echo "$(echo "${episode}" | ${my_awk} -F'E' '{print $1}' | ${my_sed} -e 's|[^0-9]||g')*1" | bc)
                let aired_season=${aired_season_numeral}

                if [ ${aired_season} -lt 10 ]; then
                    aired_season="0${aired_season_numeral}"
                fi

                aired_episode_numeral=$(echo "$(echo "${episode}" | ${my_awk} -F'E' '{print $2}' | ${my_sed} -e 's|[^0-9]||g')*1" | bc)
                let aired_episode=${aired_episode_numeral}

                if [ ${aired_episode} -lt 10 ]; then
                    aired_episode="0${aired_episode_numeral}"
                fi

                ${debug} "Series Episode Number: S${aired_season}E${aired_episode}" 2> /dev/null

                episode_info=$(${my_curl} -L -X GET --header 'Accept: application/json' --header "Authorization: Bearer ${JWT}" "https://api.thetvdb.com/series/${series_id}/episodes/query?airedSeason=${aired_season}&airedEpisode=${aired_episode}" -s | ${my_jq} ".")
    
                # Bail if we don't have any episode info
                if [ ! -z "${episode_info}" ]; then
                    episode_name=$(echo "${episode_info}" | ${my_jq} ".data[0].episodeName" | ${my_iconv} -f utf-8 -t ascii//TRANSLIT | ${my_sed} -e 's|"||g' -e 's|:| -|g' -e 's|?| |g' -e 's|  | |g' -e 's| ,|,|g' -e 's| $||g' -e 's|\(([0-9]*\)\/\([0-9]*)\)|\1 of \2|g' -e 's|/|-|g')

                    ${debug} "Series Episode Name: ${episode_name}" 2> /dev/null
    
                    # Generate shell code for relocation and cleanup, provided that ${series_name} and ${episode_name} are defined
                    if [ "${series_name}" != "null" -a "${episode_name}" != "null" ]; then
                        ${debug} "## Rename command:" 2> /dev/null
                        echo "${my_mv} \"${input_dir}/${input_file}\" \"${staging_folder}/${series_name} S${aired_season}E${aired_episode} - ${episode_name}.${file_extension}\""
    
                        if [ "${input_dir}" != "." -a "${input_dir}" != "${incoming_folder}" -a "${input_dir}" != "/" -a "${input_dir}" != "/tmp" -a "${batch}" != "true" ]; then
                            echo "${my_rm} -rf \"${input_dir}\""
                        fi
    
                    else
                        err_msg="Input file '${input_file_name}' yielded a series name of '${series_name}' and episode name of '${episode_name}'"
                        let exit_code=${ERROR}
                    fi
    
                else
                    err_msg="Input file '${input_file_name}' yielded no episode information"
                    let exit_code=${ERROR}
                fi
    
            else
                err_msg="Could not determine episode number from Input file '${input_file_name}'"
                let exit_code=${ERROR}
            fi
    
        else
            err_msg="Input file '${input_file_name}' yielded no series information"
            let exit_code=${ERROR}
        fi
    
    else
        err_msg="Cannot proceed without both an input file and a valid API JWT"
        let exit_code=${ERROR}
    fi

fi

# WHAT: Complain if necessary then exit
# WHY:  Success or failure, either way we are through!
#
if [ ${exit_code} -ne ${SUCCESS} ]; then

    if [ ! -z "${err_msg}" ]; then
        echo ""                                                                 >&2
        echo "    ERROR:  ${err_msg} ... processing halted"                     >&2
        echo ""                                                                 >&2
        echo "    USAGE: ${0} <path to tv show file> [debug|batch|batch-debug]" >&2
        echo ""                                                                 >&2
    fi

fi

exit ${exit_code}

### EXAMPLE code ###
# Series info
#curl -L -X GET --header 'Accept: application/json' --header "Authorization: Bearer ${JWT}" 'https://api.thetvdb.com/search/series?name=blindspot' | jq "."

# Series specific episode info:
#curl -L -X GET --header 'Accept: application/json' --header 'Authorization: Bearer ${JWT}' 'https://api.thetvdb.com/series/295647/episodes/query?airedSeason=1&airedEpisode=1'

# Parsing episode name
#echo "star.wars.resistance.s01e12.720p.web.x264-tbs[eztv].mkv" | awk -F'[Ss][0-9]*[Ee][0-9]*' '{print $1}' | sed -e 's|[^a-zA-Z\-]| |g' -e 's| |%20|g'

# Parsing episode number
#echo "Vikings.S05E18.1080p.WEB.H264-METCON.mkv" | sed 's|^.*\([Ss][0-9]*[Ee][0-9]*\).*$|\1|g' | tr '[a-z]' '[A-Z]'

