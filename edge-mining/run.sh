#!/usr/bin/with-contenv bashio
set -e

# Constants for integrations
SUPERVISOR_API="http://supervisor"

# Voltronic integration (custom add-on)
CUSTOM_REPO="https://github.com/GitGab19/addon-voltronic-inverters"
CUSTOM_ADDON_SLUG="ec05b559_voltronic"

# SolarEdge integration (clone from GitHub)
SOLAREDGE_REPO="https://github.com/WillCodeForCats/solaredge-modbus-multi"
SOLAREDGE_COMPONENTS_PATH="/config/custom_components/solaredge_modbus_multi"

# Miner integration repository (for Bitcoin mining)
MINER_REPO="https://github.com/Schnitzel/hass-miner"
CUSTOM_COMPONENTS_PATH="/config/custom_components/miner"

# Read add-on options
INVERTER_TYPE=$(bashio::config 'inverter_type')
BROKER_HOST=$(bashio::config 'mqtt_broker_host')
USERNAME=$(bashio::config 'mqtt_username')
PASSWORD=$(bashio::config 'mqtt_password')
MINER_IP=$(bashio::config 'miner_ip')
MINER_USERNAME=$(bashio::config 'miner_username')
MINER_PASSWORD=$(bashio::config 'miner_password')
MINER_TITLE=$(bashio::config 'miner_name')
SOLAREDGE_IP=$(bashio::config 'solaredge_ip')
SOLAREDGE_PORT=$(bashio::config 'solaredge_port')
SOLAREDGE_MODBUS_ADDRESS=$(bashio::config 'solaredge_modbus_address')

bashio::log.info "Starting Edge Mining setup script..."

##################################################
# 1. (Voltronic only) Install and start EMQX add-on
##################################################
if [ "$INVERTER_TYPE" == "voltronic" ]; then
  bashio::log.info "Inverter type is voltronic. Checking EMQX add-on status..."
  INFO_RESPONSE=$(curl -s -X GET -H "Authorization: Bearer $SUPERVISOR_TOKEN" "$SUPERVISOR_API/addons/a0d7b954_emqx/info")
  IS_INSTALLED=$(echo "$INFO_RESPONSE" | jq -r '.data.installed')
  if [ "$IS_INSTALLED" == "false" ]; then
    bashio::log.notice "EMQX is not installed. Installing..."
    INSTALL_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" -d '{}' \
      "$SUPERVISOR_API/addons/a0d7b954_emqx/install")
    if [ "$(echo "$INSTALL_RESPONSE" | jq -r '.result')" != "ok" ]; then
      bashio::log.error "Failed to install EMQX add-on!"
      echo "$INSTALL_RESPONSE"
      exit 1
    fi
    bashio::log.info "EMQX add-on installed successfully!"
  else
    bashio::log.info "EMQX add-on is already installed."
  fi

  bashio::log.info "Starting EMQX add-on..."
  START_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" -d '{}' \
    "$SUPERVISOR_API/addons/a0d7b954_emqx/start")
  if [ "$(echo "$START_RESPONSE" | jq -r '.result')" != "ok" ]; then
    bashio::log.error "Failed to start EMQX add-on!"
    echo "$START_RESPONSE"
    exit 1
  fi
  bashio::log.info "EMQX add-on is running!"
fi

##################################################
# 2. (Voltronic only) Configure MQTT integration in HA
##################################################
if [ "$INVERTER_TYPE" == "voltronic" ]; then
  bashio::log.info "Configuring MQTT integration in Home Assistant..."
  EXISTING_ENTRIES=$(curl -s -X GET -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    "$SUPERVISOR_API/core/api/config/config_entries/entry")
  MQTT_EXISTS=$(echo "$EXISTING_ENTRIES" | jq -r '.[] | select(.domain == "mqtt")')
  if [ -z "$MQTT_EXISTS" ]; then
    bashio::log.notice "MQTT integration is not configured. Starting configuration..."
    FLOW_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" -d '{"handler": "mqtt"}' \
      "$SUPERVISOR_API/core/api/config/config_entries/flow")
    FLOW_ID=$(echo "$FLOW_RESPONSE" | jq -r '.flow_id')
    if [ -z "$FLOW_ID" ]; then
      bashio::log.error "Failed to create an MQTT configuration flow!"
      echo "$FLOW_RESPONSE"
      exit 1
    fi
    bashio::log.info "MQTT configuration flow created with ID: $FLOW_ID"
    while true; do
      STEP_RESPONSE=$(curl -s -X GET -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
        "$SUPERVISOR_API/core/api/config/config_entries/flow/$FLOW_ID")
      STEP_TYPE=$(echo "$STEP_RESPONSE" | jq -r '.type')
      STEP_ID=$(echo "$STEP_RESPONSE" | jq -r '.step_id')
      bashio::log.info "MQTT config: step type $STEP_TYPE (ID: $STEP_ID)"
      if [ "$STEP_TYPE" == "menu" ]; then
        curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
          -H "Content-Type: application/json" -d '{"next_step_id": "broker"}' \
          "$SUPERVISOR_API/core/api/config/config_entries/flow/$FLOW_ID"
      elif [ "$STEP_TYPE" == "form" ]; then
        CONFIG_STEP_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
          -H "Content-Type: application/json" -d "{
                  \"broker\": \"$BROKER_HOST\",
                  \"port\": 1883,
                  \"username\": \"$USERNAME\",
                  \"password\": \"$PASSWORD\"
                }" "$SUPERVISOR_API/core/api/config/config_entries/flow/$FLOW_ID")
        if [[ "$(echo "$CONFIG_STEP_RESPONSE" | jq -r '.type')" == "create_entry" ]]; then
          bashio::log.info "MQTT successfully configured!"
          break
        else
          bashio::log.error "Error during MQTT configuration!"
          echo "$CONFIG_STEP_RESPONSE"
          exit 1
        fi
      elif [ "$STEP_TYPE" == "progress" ]; then
        bashio::log.info "Waiting for MQTT config step $STEP_ID..."
        sleep 5
      elif [ "$STEP_TYPE" == "create_entry" ]; then
        bashio::log.info "MQTT successfully configured!"
        break
      else
        bashio::log.error "Unknown MQTT config step: $STEP_TYPE"
        echo "$STEP_RESPONSE"
        exit 1
      fi
    done
  else
    bashio::log.info "MQTT integration is already configured."
  fi
else
  bashio::log.info "Inverter type is solaredge. Skipping MQTT configuration."
fi

#########################################################
# 3. Install the appropriate integration based on type #
#########################################################
if [ "$INVERTER_TYPE" == "voltronic" ]; then
  bashio::log.info "Using Voltronic integration. Installing Voltronic add-on..."
  EXISTING_REPOS=$(curl -s -X GET -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    "$SUPERVISOR_API/store/repositories" | jq -r '.data[] | select(.source == "'"$CUSTOM_REPO"'")')
  if [ -z "$EXISTING_REPOS" ]; then
    bashio::log.notice "Custom repository not found. Adding..."
    ADD_REPO_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" -d "{\"repository\": \"$CUSTOM_REPO\"}" \
      "$SUPERVISOR_API/store/repositories")
    if [ "$(echo "$ADD_REPO_RESPONSE" | jq -r '.result')" != "ok" ]; then
      bashio::log.error "Failed to add custom repository!"
      echo "$ADD_REPO_RESPONSE"
      exit 1
    fi
    bashio::log.info "Custom repository added."
  else
    bashio::log.info "Custom repository already present."
  fi
  bashio::log.info "Checking Voltronic add-on status..."
  ADDON_INFO=$(curl -s -X GET -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    "$SUPERVISOR_API/addons/$CUSTOM_ADDON_SLUG/info")
  IS_ADDON_INSTALLED=$(echo "$ADDON_INFO" | jq -r '.data.installed')
  if [ "$IS_ADDON_INSTALLED" == "false" ]; then
    bashio::log.notice "Voltronic add-on not installed. Installing..."
    INSTALL_CUSTOM_ADDON=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" -d '{}' \
      "$SUPERVISOR_API/addons/$CUSTOM_ADDON_SLUG/install")
    if [ "$(echo "$INSTALL_CUSTOM_ADDON" | jq -r '.result')" != "ok" ]; then
      bashio::log.error "Failed to install Voltronic add-on!"
      echo "$INSTALL_CUSTOM_ADDON"
      exit 1
    fi
    bashio::log.info "Voltronic add-on installed."
  else
    bashio::log.info "Voltronic add-on already installed."
  fi
  bashio::log.info "Starting Voltronic add-on..."
  START_VOLTRONIC_ADDON=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" -d '{}' \
    "$SUPERVISOR_API/addons/$CUSTOM_ADDON_SLUG/start")
  if [ "$(echo "$START_VOLTRONIC_ADDON" | jq -r '.result')" != "ok" ]; then
    bashio::log.error "Failed to start Voltronic add-on!"
    echo "$START_VOLTRONIC_ADDON"
    exit 1
  fi
  bashio::log.info "Voltronic add-on is running!"

elif [ "$INVERTER_TYPE" == "solaredge" ]; then
  bashio::log.info "Using SolarEdge integration. Installing SolarEdge integration..."
  if [ -d "$SOLAREDGE_COMPONENTS_PATH" ]; then
    bashio::log.info "SolarEdge integration already installed at $SOLAREDGE_COMPONENTS_PATH."
  else
    bashio::log.notice "SolarEdge integration not found. Cloning repository..."
    TEMP_SE_DIR="/tmp/solaredge-modbus-multi"
    bashio::log.info "Cloning SolarEdge repository to $TEMP_SE_DIR..."
    if git clone "$SOLAREDGE_REPO" "$TEMP_SE_DIR"; then
      bashio::log.info "SolarEdge repository cloned successfully."
      bashio::log.info "Ensuring custom_components directory exists..."
      if mkdir -p "$(dirname "$SOLAREDGE_COMPONENTS_PATH")"; then
        bashio::log.info "Directory $(dirname "$SOLAREDGE_COMPONENTS_PATH") is ready."
      else
        bashio::log.error "Failed to create directory $(dirname "$SOLAREDGE_COMPONENTS_PATH")."
        exit 1
      fi
      bashio::log.info "Copying SolarEdge integration files to $SOLAREDGE_COMPONENTS_PATH..."
      if cp -r "$TEMP_SE_DIR/custom_components/solaredge_modbus_multi" "$SOLAREDGE_COMPONENTS_PATH"; then
        bashio::log.info "SolarEdge integration files copied successfully."
      else
        bashio::log.error "Failed to copy SolarEdge integration files."
        exit 1
      fi
      bashio::log.info "Cleaning up temporary files..."
      rm -rf "$TEMP_SE_DIR"
      bashio::log.info "Temporary files cleaned up."
      bashio::log.notice "Restarting Home Assistant to apply changes..."
      if curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" "$SUPERVISOR_API/core/restart"; then
        bashio::log.info "Home Assistant restart initiated."
      else
        bashio::log.error "Failed to restart Home Assistant."
        exit 1
      fi
    else
      bashio::log.error "Failed to clone SolarEdge repository."
      exit 1
    fi
  fi

  bashio::log.info "Configuring SolarEdge integration in Home Assistant..."
  EXISTING_SE_ENTRY=$(curl -s -X GET -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    "$SUPERVISOR_API/core/api/config/config_entries/entry" | jq -r '.[] | select(.domain == "solaredge_modbus_multi")')
  if [ -z "$EXISTING_SE_ENTRY" ]; then
    bashio::log.notice "SolarEdge integration is not configured. Starting configuration..."
    SOLAREDGE_FLOW=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" -d '{"handler": "solaredge_modbus_multi"}' \
      "$SUPERVISOR_API/core/api/config/config_entries/flow")
    SOLAREDGE_FLOW_ID=$(echo "$SOLAREDGE_FLOW" | jq -r '.flow_id')
    if [ -z "$SOLAREDGE_FLOW_ID" ]; then
      bashio::log.error "Failed to start SolarEdge configuration flow!"
      echo "$SOLAREDGE_FLOW"
      exit 1
    fi
    bashio::log.info "Submitting SolarEdge configuration..."
    CONFIGURE_SOLAREDGE=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" -d "{
            \"name\": \"SolarEdge\",
            \"host\": \"$(bashio::config 'solaredge_ip')\",
            \"port\": $(bashio::config 'solaredge_port'),
            \"device_list\": \"1\"
          }" "$SUPERVISOR_API/core/api/config/config_entries/flow/$SOLAREDGE_FLOW_ID")
    if [[ "$(echo "$CONFIGURE_SOLAREDGE" | jq -r '.type')" == "create_entry" ]]; then
      bashio::log.info "SolarEdge integration configured successfully!"
    else
      bashio::log.error "Failed to configure SolarEdge integration!"
      echo "$CONFIGURE_SOLAREDGE"
      exit 1
    fi
  else
    bashio::log.info "SolarEdge integration is already configured."
  fi

else
  bashio::log.error "Unsupported inverter type: $INVERTER_TYPE"
  exit 1
fi

###################################################
# 5. Check and clone the miner integration repo   #
###################################################
bashio::log.info "Checking if the miner integration is already installed..."
if [ -d "$CUSTOM_COMPONENTS_PATH" ]; then
  bashio::log.info "Miner integration is already installed at $CUSTOM_COMPONENTS_PATH."
else
  bashio::log.notice "Miner integration is not installed. Proceeding with installation..."
  TEMP_DIR="/tmp/hass-miner"
  bashio::log.info "Cloning the miner repository to $TEMP_DIR..."
  if git clone "$MINER_REPO" "$TEMP_DIR"; then
    bashio::log.info "Miner repository cloned successfully."
    bashio::log.info "Ensuring the custom_components directory exists..."
    if mkdir -p "$(dirname "$CUSTOM_COMPONENTS_PATH")"; then
      bashio::log.info "Directory $(dirname "$CUSTOM_COMPONENTS_PATH") is ready."
    else
      bashio::log.error "Failed to create directory $(dirname "$CUSTOM_COMPONENTS_PATH"). Check permissions."
      exit 1
    fi
    bashio::log.info "Copying miner integration files to $CUSTOM_COMPONENTS_PATH..."
    if cp -r "$TEMP_DIR/custom_components/miner" "$CUSTOM_COMPONENTS_PATH"; then
      bashio::log.info "Miner integration files copied successfully."
    else
      bashio::log.error "Failed to copy miner integration files. Check permissions and paths."
      exit 1
    fi
    bashio::log.info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    bashio::log.info "Temporary files cleaned up."
    bashio::log.notice "Restarting Home Assistant to apply changes..."
    if curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" "$SUPERVISOR_API/core/restart"; then
      bashio::log.info "Home Assistant restart initiated."
    else
      bashio::log.error "Failed to restart Home Assistant. Check the supervisor API."
      exit 1
    fi
  else
    bashio::log.error "Failed to clone the miner repository. Check network and repository URL."
    exit 1
  fi
fi

#############################################
# 6. Configure the miner integration        #
#############################################
bashio::log.info "Checking if the miner integration is already configured..."
EXISTING_MINER_ENTRY=$(curl -s -X GET -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
  "$SUPERVISOR_API/core/api/config/config_entries/entry" | jq -r '.[] | select(.domain == "miner")')
if [ -z "$EXISTING_MINER_ENTRY" ]; then
  bashio::log.notice "The miner integration is not configured. Proceeding with configuration..."
  MINER_FLOW=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" -d '{"handler": "miner"}' \
    "$SUPERVISOR_API/core/api/config/config_entries/flow")
  MINER_FLOW_ID=$(echo "$MINER_FLOW" | jq -r '.flow_id')
  if [ -z "$MINER_FLOW_ID" ]; then
    bashio::log.error "Failed to start the configuration flow for the miner integration!"
    echo "$MINER_FLOW"
    exit 1
  fi
  while true; do
    STEP_RESPONSE=$(curl -s -X GET -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      "$SUPERVISOR_API/core/api/config/config_entries/flow/$MINER_FLOW_ID")
    STEP_TYPE=$(echo "$STEP_RESPONSE" | jq -r '.type')
    STEP_ID=$(echo "$STEP_RESPONSE" | jq -r '.step_id')
    if [ -z "$STEP_TYPE" ]; then
      bashio::log.error "Unexpected empty response during configuration flow!"
      echo "$STEP_RESPONSE"
      exit 1
    fi
    bashio::log.info "Processing step: $STEP_ID (type: $STEP_TYPE)..."
    case "$STEP_ID" in
      user)
        bashio::log.info "Submitting miner IP address: $MINER_IP"
        STEP_PAYLOAD="{\"ip\": \"$MINER_IP\"}"
        ;;
      login)
        bashio::log.info "Submitting miner login credentials..."
        STEP_PAYLOAD="{
          \"web_username\": \"$MINER_USERNAME\",
          \"web_password\": \"$MINER_PASSWORD\"
        }"
        ;;
      title)
        bashio::log.info "Submitting miner title: $MINER_TITLE"
        STEP_PAYLOAD="{\"title\": \"$MINER_TITLE\"}"
        ;;
      create_entry)
        bashio::log.info "Miner integration configured successfully!"
        break
        ;;
      *)
        bashio::log.error "Unhandled step type: $STEP_ID"
        echo "$STEP_RESPONSE"
        exit 1
        ;;
    esac
    STEP_RESULT=$(curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" -d "$STEP_PAYLOAD" \
      "$SUPERVISOR_API/core/api/config/config_entries/flow/$MINER_FLOW_ID")
    if [[ "$(echo "$STEP_RESULT" | jq -r '.type')" == "create_entry" ]]; then
      bashio::log.info "Miner integration configured successfully!"
      break
    elif [[ "$(echo "$STEP_RESULT" | jq -r '.type')" == "form" ]]; then
      bashio::log.info "Continuing with the next form step..."
    else
      bashio::log.error "Unexpected response during configuration!"
      echo "$STEP_RESULT"
      exit 1
    fi
  done
else
  bashio::log.info "The miner integration is already configured."
fi

bashio::log.info "Edge Mining setup script completed successfully!"