#!/usr/bin/with-contenv bashio
set -e

SUPERVISOR_API="http://supervisor"
EMQX_ADDON_SLUG="a0d7b954_emqx"
CUSTOM_REPO="https://github.com/GitGab19/addon-voltronic-inverters"
CUSTOM_ADDON_SLUG="ec05b559_voltronic"
MINER_REPO="https://github.com/Schnitzel/hass-miner"
CUSTOM_COMPONENTS_PATH="/config/custom_components/miner"

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

# 3. Configure the MQTT integration
bashio::log.info "Configuring the MQTT integration in Home Assistant..."

EXISTING_ENTRIES=$(curl -s -X GET \
  -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  "$SUPERVISOR_API/core/api/config/config_entries/entry")

MQTT_EXISTS=$(echo "$EXISTING_ENTRIES" | jq -r '.[] | select(.domain == "mqtt")')

if [ -z "$MQTT_EXISTS" ]; then
  bashio::log.notice "MQTT integration is not configured. Starting configuration..."
  FLOW_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"handler": "mqtt"}' \
    "$SUPERVISOR_API/core/api/config/config_entries/flow")

  FLOW_ID=$(echo "$FLOW_RESPONSE" | jq -r '.flow_id')

  if [ -z "$FLOW_ID" ]; then
    bashio::log.error "Failed to create an MQTT configuration flow!"
    echo "$FLOW_RESPONSE"
    exit 1
  fi

  bashio::log.info "MQTT configuration flow created with ID: $FLOW_ID"

  while true; do
    STEP_RESPONSE=$(curl -s -X GET \
      -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      "$SUPERVISOR_API/core/api/config/config_entries/flow/$FLOW_ID")

    STEP_TYPE=$(echo "$STEP_RESPONSE" | jq -r '.type')
    STEP_ID=$(echo "$STEP_RESPONSE" | jq -r '.step_id')

    bashio::log.info "Current step type: $STEP_TYPE (ID: $STEP_ID)"

    if [ "$STEP_TYPE" == "menu" ]; then
      bashio::log.info "Selecting the 'broker' option from the menu..."
      curl -s -X POST \
        -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"next_step_id": "broker"}' \
        "$SUPERVISOR_API/core/api/config/config_entries/flow/$FLOW_ID"

    elif [ "$STEP_TYPE" == "form" ]; then
      bashio::log.info "Entering broker details..."
      CONFIG_STEP_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
              \"broker\": \"$BROKER_HOST\",
              \"port\": 1883,
              \"username\": \"$USERNAME\",
              \"password\": \"$PASSWORD\"
            }" \
        "$SUPERVISOR_API/core/api/config/config_entries/flow/$FLOW_ID")

      if [[ "$(echo "$CONFIG_STEP_RESPONSE" | jq -r '.type')" == "create_entry" ]]; then
        bashio::log.info "MQTT successfully configured!"
        break
      else
        bashio::log.error "Something went wrong during the MQTT configuration!"
        echo "$CONFIG_STEP_RESPONSE"
        exit 1
      fi

    elif [ "$STEP_TYPE" == "progress" ]; then
      bashio::log.info "Waiting for process completion: $STEP_ID..."
      sleep 5

    elif [ "$STEP_TYPE" == "create_entry" ]; then
      bashio::log.info "MQTT successfully configured!"
      break

    else
      bashio::log.error "Unknown step type: $STEP_TYPE."
      echo "$STEP_RESPONSE"
      exit 1
    fi
  done
else
  bashio::log.info "MQTT integration is already configured."
fi

# 4. Check and install the custom repository and Voltronic add-on
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

# Install the Voltronic add-on
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

# 5. Check and clone the miner repository if missing
bashio::log.info "Checking if the miner integration is already installed..."
if [ -d "$CUSTOM_COMPONENTS_PATH" ]; then
  bashio::log.info "Miner integration is already installed at $CUSTOM_COMPONENTS_PATH."
else
  bashio::log.notice "Miner integration is not installed. Proceeding with installation..."

  TEMP_DIR="/tmp/hass-miner"
  bashio::log.info "Cloning the repository to $TEMP_DIR..."
  if git clone "$MINER_REPO" "$TEMP_DIR"; then
    bashio::log.info "Repository cloned successfully."

    # Ensure the custom_components directory exists
    bashio::log.info "Ensuring the custom components directory exists..."
    if mkdir -p "$(dirname "$CUSTOM_COMPONENTS_PATH")"; then
      bashio::log.info "Directory $(dirname "$CUSTOM_COMPONENTS_PATH") created or already exists."
    else
      bashio::log.error "Failed to create directory $(dirname "$CUSTOM_COMPONENTS_PATH"). Check permissions."
      exit 1
    fi

    # Copy the miner files
    bashio::log.info "Copying miner integration files to $CUSTOM_COMPONENTS_PATH..."
    if cp -r "$TEMP_DIR/custom_components/miner" "$CUSTOM_COMPONENTS_PATH"; then
      bashio::log.info "Miner integration files copied successfully."
    else
      bashio::log.error "Failed to copy miner integration files. Check permissions and paths."
      exit 1
    fi

    # Clean up
    bashio::log.info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    bashio::log.info "Temporary files cleaned up."

    # Restart Home Assistant
    bashio::log.notice "Restarting Home Assistant to apply changes..."
    if curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" "$SUPERVISOR_API/core/restart"; then
      bashio::log.info "Home Assistant restart initiated."
    else
      bashio::log.error "Failed to restart Home Assistant. Check the supervisor API."
      exit 1
    fi
  else
    bashio::log.error "Failed to clone the repository. Check network and repository URL."
    exit 1
  fi
fi

# 6. Configure the miner integration
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