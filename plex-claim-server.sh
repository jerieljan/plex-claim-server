#!/bin/bash

# If we are debugging, enable trace
if [ "${DEBUG,,}" = "true" ]; then
  set -x
fi

function getPref {
  local key="$1"
  sed -n -E "s/^.*${key}=\"([^\"]*)\".*$/\1/p" "${prefFile}"
}

function setPref {
  local key="$1"
  local value="$2"

  count="$(grep -c "${key}" "${prefFile}")"
  count=$(($count + 0))
  if [[ $count > 0 ]]; then
    sed -i -E "s/${key}=\"([^\"]*)\"/${key}=\"$value\"/" "${prefFile}"
  else
    sed -i -E "s/\/>/ ${key}=\"$value\"\/>/" "${prefFile}"
  fi
}

# These were in the original file — it won't be used at all and thankfully, nothing else uses this besides the line below.
home="$(echo ~plex)"
pmsApplicationSupportDir="${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR:-${home}/Library/Application Support}"

# This has been modified to use the fixed directory where Plex lives on a Synology NAS.
prefFile="/volume1/PlexMediaServer/AppData/Plex Media Server/Preferences.xml"

PLEX_CLAIM="$1"

# Create empty shell pref file if it doesn't exist already
# We're also changing the preferences file ownership to PlexMediaServer.
if [ ! -e "${prefFile}" ]; then
  echo "Creating pref shell"
  mkdir -p "$(dirname "${prefFile}")"
  cat > "${prefFile}" <<-EOF
<?xml version="1.0" encoding="utf-8"?>
<Preferences/>
EOF
  sudo chown -R PlexMediaServer:PlexMediaServer "$(dirname "${prefFile}")"
fi

# Setup Server's client identifier
serial="$(getPref "MachineIdentifier")"
if [ -z "${serial}" ]; then
  serial="$(uuidgen)"
  setPref "MachineIdentifier" "${serial}"
fi
clientId="$(getPref "ProcessedMachineIdentifier")"
if [ -z "${clientId}" ]; then
  clientId="$(echo -n "${serial}- Plex Media Server" | sha1sum | cut -b 1-40)"
  setPref "ProcessedMachineIdentifier" "${clientId}"
fi

# Get server token and only turn claim token into server token if we have former but not latter.
token="$(getPref "PlexOnlineToken")"
if [ ! -z "${PLEX_CLAIM}" ] && [ -z "${token}" ]; then
  echo "Attempting to obtain server token from claim token"
  loginInfo="$(curl -X POST \
        -H 'X-Plex-Client-Identifier: '${clientId} \
        -H 'X-Plex-Product: Plex Media Server'\
        -H 'X-Plex-Version: 1.1' \
        -H 'X-Plex-Provides: server' \
        -H 'X-Plex-Platform: Linux' \
        -H 'X-Plex-Platform-Version: 1.0' \
        -H 'X-Plex-Device-Name: PlexMediaServer' \
        -H 'X-Plex-Device: Linux' \
        "https://plex.tv/api/claim/exchange?token=${PLEX_CLAIM}")"
  token="$(echo "$loginInfo" | sed -n 's/.*<authentication-token>\(.*\)<\/authentication-token>.*/\1/p')"

  if [ "$token" ]; then
    setPref "PlexOnlineToken" "${token}"
    echo "Plex Media Server successfully claimed"
  fi
fi
