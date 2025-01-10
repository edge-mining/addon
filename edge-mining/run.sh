#!/usr/bin/with-contenv bashio
set -e

SUPERVISOR_API="http://supervisor"
EMQX_ADDON_SLUG="a0d7b954_emqx"
CUSTOM_REPO="https://github.com/GitGab19/addon-voltronic-inverters"
CUSTOM_ADDON_SLUG="ec05b559_voltronic"
MINER_REPO="https://github.com/Schnitzel/hass-miner"

# Read add-on options
BROKER_HOST=$(bashio::config 'broker_host')
USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')
MINER_IP=$(bashio::config 'miner_ip')  # Read the miner IP from options

bashio::log.info "Starting Edge Mining setup script..."

# 1. Check if the EMQX add-on is already installed
bashio::log.info "Checking the status of the EMQX add-on..."
INFO_RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  "$SUPERVISOR_API/addons/$EMQX_ADDON_SLUG/info")

IS_INSTALLED=$(echo "$INFO_RESPONSE" | jq -r '.data.installed')

if [ "$IS_INSTALLED" == "false" ]; then
  bashio::log.notice "EMQX is not installed. Installing..."
  INSTALL_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "$SUPERVISOR_API/addons/$EMQX_ADDON_SLUG/install")

  if [ "$(echo "$INSTALL_RESPONSE" | jq -r '.result')" != "ok" ]; then
    bashio::log.error "Failed to install the EMQX add-on!"
    echo "$INSTALL_RESPONSE"
    exit 1
  fi
  bashio::log.info "EMQX add-on installed successfully!"
else
  bashio::log.info "EMQX add-on is already installed."
fi

# 2. Start the EMQX add-on
bashio::log.info "Starting the EMQX add-on..."
START_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "$SUPERVISOR_API/addons/$EMQX_ADDON_SLUG/start")

if [ "$(echo "$START_RESPONSE" | jq -r '.result')" != "ok" ]; then
  bashio::log.error "Failed to start the EMQX add-on!"
  echo "$START_RESPONSE"
  exit 1
fi

bashio::log.info "EMQX add-on is running!"

# 3. Check and install the custom repository and Voltronic add-on
bashio::log.info "Checking if the custom repository is present..."
EXISTING_REPOS=$(curl -s -X GET \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  "$SUPERVISOR_API/store/repositories" | jq -r '.data[] | select(.source == "'"$CUSTOM_REPO"'")')

if [ -z "$EXISTING_REPOS" ]; then
  bashio::log.notice "Custom repository is not present. Adding..."
  ADD_REPO_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"repository\": \"$CUSTOM_REPO\"}" \
    "$SUPERVISOR_API/store/repositories")

  if [ "$(echo "$ADD_REPO_RESPONSE" | jq -r '.result')" != "ok" ]; then
    bashio::log.error "Failed to add the custom repository!"
    echo "$ADD_REPO_RESPONSE"
    exit 1
  fi
  bashio::log.info "Custom repository added successfully!"
else
  bashio::log.info "Custom repository is already present."
fi

# Check if the Voltronic add-on is installed
bashio::log.info "Checking the status of the Voltronic add-on..."
ADDON_INFO=$(curl -s -X GET \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  "$SUPERVISOR_API/addons/$CUSTOM_ADDON_SLUG/info")

IS_ADDON_INSTALLED=$(echo "$ADDON_INFO" | jq -r '.data.installed')

if [ "$IS_ADDON_INSTALLED" == "false" ]; then
  bashio::log.notice "Voltronic add-on is not installed. Installing..."
  INSTALL_CUSTOM_ADDON=$(curl -s -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "$SUPERVISOR_API/addons/$CUSTOM_ADDON_SLUG/install")

  if [ "$(echo "$INSTALL_CUSTOM_ADDON" | jq -r '.result')" != "ok" ]; then
    bashio::log.error "Failed to install the Voltronic add-on!"
    echo "$INSTALL_CUSTOM_ADDON"
    exit 1
  fi
  bashio::log.info "Voltronic add-on installed successfully!"
else
  bashio::log.info "Voltronic add-on is already installed."
fi

# Start the Voltronic add-on
bashio::log.info "Starting the Voltronic add-on..."
START_VOLTRONIC_ADDON=$(curl -s -X POST \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "$SUPERVISOR_API/addons/$CUSTOM_ADDON_SLUG/start")

if [ "$(echo "$START_VOLTRONIC_ADDON" | jq -r '.result')" != "ok" ]; then
  bashio::log.error "Failed to start the Voltronic add-on!"
  echo "$START_VOLTRONIC_ADDON"
  exit 1
fi

bashio::log.info "Voltronic add-on is running!"

# 4. Configure the miner integration
bashio::log.info "Checking if the miner integration is already configured..."
EXISTING_MINER_ENTRY=$(curl -s -X GET \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  "$SUPERVISOR_API/core/api/config/config_entries/entry" | jq -r '.[] | select(.domain == "miner")')

if [ -z "$EXISTING_MINER_ENTRY" ]; then
  bashio::log.notice "The miner integration is not configured. Proceeding with configuration..."

  MINER_FLOW=$(curl -s -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"handler": "miner"}' \
    "$SUPERVISOR_API/core/api/config/config_entries/flow")

  MINER_FLOW_ID=$(echo "$MINER_FLOW" | jq -r '.flow_id')

  bashio::log.info "Submitting miner IP address: $MINER_IP"
  CONFIGURE_MINER=$(curl -s -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"ip\": \"$MINER_IP\"}" \
    "$SUPERVISOR_API/core/api/config/config_entries/flow/$MINER_FLOW_ID")

  if [[ "$(echo "$CONFIGURE_MINER" | jq -r '.type')" == "create_entry" ]]; then
    bashio::log.info "Miner integration configured successfully!"
  else
    bashio::log.error "Failed to configure the miner integration!"
    echo "$CONFIGURE_MINER"
    exit 1
  fi
else
  bashio::log.info "The miner integration is already configured."
fi

bashio::log.info "Edge Mining setup script completed successfully!"