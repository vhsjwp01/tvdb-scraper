SOURCE		= tvdb_scrape.sh
TARGET_DIR	= /usr/local/bin
PLATFORM	= $(shell uname -s)

install:
	if [ ! -d "${TARGET_DIR}" ]; then                                                         \
	    mkdir -p "${TARGET_DIR}"                                                            ; \
	fi                                                                                      ; \
	case "${PLATFORM}" in                                                                     \
	    Darwin|Linux)                                                                         \
	        cp "${SOURCE}" "${TARGET_DIR}/${SOURCE}"                                       && \
	        chmod 755 "${TARGET_DIR}/${SOURCE}"                                               \
	    ;;                                                                                    \
	    *)                                                                                    \
	        echo "Unknown (and unsupported) platform: ${PLATFORM}"                            \
	    ;;                                                                                    \
	esac
