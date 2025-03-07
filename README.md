# ⚡ Edge Mining ⚡

Bitcoin mining can turn excess energy into economic value, making it an ideal solution for renewable energy plants with surplus production.
Mining is highly flexible: it can be activated when there’s excess energy and instantly shut down when needed elsewhere. Additionally, the heat generated can be repurposed for heating, maximizing overall efficiency.

Edge Mining is an add-on for Home Assistant that automates the installation of all necessary components to communicate with a photovoltaic system’s inverter and the mining hardware. It simplifies the configuration process, reducing it to just a few fields that the user needs to fill in, making mining integration effortless and accessible.

Once set up, users only need to create their own Home Assistant dashboard and configure their automations. We also plan to integrate a pre-built dashboard and automations in future updates.

---

# 🔧 Getting Started

Follow these instructions to create a mining setup integrated with Home Assistant to manage an ASIC miner based on your energy availability.

## 📋 Prerequisites

Before you begin, make sure you have the following:

- **Raspberry Pi 4** (or another dedicated device)
- **Home Assistant** with **HACS** installed ([HACS installation guide](https://www.hacs.xyz/docs/use/download/download/#to-download-hacs))
- **Compatible inverter**: Solaredge and Voltronic (Axpert, MPP Solar PIP, Voltacon or Effekta).
- **ASIC miner** with a static IP, running **BraiinsOS** ([BraiinsOS installation guide](https://braiins.com/os-firmware))

## 💾 Edge Mining Installation

Now the first thing you need to do is to install the Edge Mining add-on by clicking the following button:

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fedge-mining%2Faddon-edge-mining)

Edge Mining will automatically install various add-ons and integrations into Home Assistant for its own use, depending on the selected inverter.

### General Installations

- **[HASS-miner](https://github.com/Schnitzel/hass-miner)** – Enables seamless control and monitoring of ASIC miners.

### For Voltronic:

- **[MQTT](https://github.com/home-assistant/core/tree/dev/homeassistant/components/mqtt)** (intergation) – Acts as a communication bridge between system components.
- **[EMQX](https://github.com/hassio-addons/addon-emqx)** (add-on) – A high-performance MQTT broker that ensures reliable and scalable communication between components.
- **[Voltronic](https://github.com/GitGab19/addon-voltronic-inverters)** (add-on) – Designed to integrate and manage Voltronic inverters, enabling real-time monitoring.

### For Solaredge

- **[Solaredge Modbus Multi](https://github.com/WillCodeForCats/solaredge-modbus-multi)** (integration) - Provides Modbus/TCP local polling to one or more SolarEdge inverters

### Initial Configuration

Once Edge Mining is installed, before running it, a small configuration is required:

1. **Enter the miner's static IP address** to ensure stable connectivity.
2. **Enter the username and password for BraiinsOS**, which are usually `root/root` by default.
3. **Check and insert the parameters needed for Solaredge or Voltronic** inverter:
   - for Solaredge, make sure [**modbus is enabled**](https://github.com/WillCodeForCats/solaredge-modbus-multi/wiki/Configuration) on your inverter and enter `solaredge_ip`, `solaredge_port`, and `solaredge_modbus_address` fields;
   - for Voltronic, the default values on the config should be fine;
4. **Click start** and wait a bit to have all your setup ready for your first automations!

![Edge Mining Configuration](https://github.com/edge-mining/addon-edge-mining/blob/main/images/edge-mining-configuration-new.png)

After completing these steps, your system will be ready to operate with Edge Mining.
Now you are ready to set up the view and create automations based on your needs.

## 💡 Configuration Suggestions

### Create a view

Consider creating a view that includes an overall visualization of the inverter data and another view displaying data from the miner. This will allow for better monitoring and optimization of energy usage.

### Install Forecast.solar

It is recommended to install the [Forecast.solar](https://www.home-assistant.io/integrations/forecast_solar/) integration to obtain a forecast of your photovoltaic system's energy production. By providing the GPS location of your installation, along with the orientation and tilt of the panels, you can get accurate predictions of solar radiation. With Forecast.solar data, it is possible to create automation rules based on irradiation forecasts, making energy consumption adjustments more precise and efficient.

### Use a Smart Plug

Using a smart plug to control your miner's power on/off is advisable. Ensure that the chosen model has sufficient amperage to handle the miner’s high power consumption. For example, the TP-Link Tapo P110M (16A) is a reliable option for efficiently managing the miner’s power operations.


Below is an example of a recommended view setup, displaying both the inverter's overall data, the miner's performance metrics, and the smart plug control for efficient energy management.

![View Example](https://github.com/edge-mining/addon-edge-mining/blob/main/images/view-example.png)

## 🤖 Automations Example

### Introduction

One of the biggest challenges in managing a solar-powered system is efficiently utilizing all excess energy. Simple automations for turning devices on and off may work in basic scenarios, but they often lead to situations where, on clear sunny days, the battery reaches **100% charge too quickly**, even with the miner running. When this happens, surplus energy from the solar panels goes unused because the miner's power consumption may be lower than the system's maximum production.

To solve this, we are experimenting with automations that **proactively manage the miner’s operation based on daily solar production forecasts**. Instead of waiting for excess energy to accumulate, the system **starts mining earlier in the day when the battery is still low**, allowing solar energy to be used gradually throughout the day. This approach ensures that:

- The battery charges more slowly and reaches full capacity later in the day.
- The solar system operates at **maximum efficiency**, using as much available energy as possible.
- There is sufficient battery storage to sustain energy needs throughout the night.

The automations described below are part of an ongoing experiment to **optimize surplus energy usage** and may evolve as we refine the system. In the future, these automations will be integrated into Edge Mining as part of its energy optimization framework.

### How the Automations Work

These Home Assistant automations are designed to efficiently manage the **switching ON and OFF** of a miner based on battery level, solar forecast, and real-time solar power availability. The goal is to maximize energy efficiency while ensuring that battery power is used optimally.

### **1. Switching ON the Miner**

The miner is turned on when there is enough stored battery energy and an expectation that upcoming solar production will be sufficient to sustain mining operations. The system evaluates both the battery’s current charge and the estimated solar energy available throughout the day to determine the best moment to start mining.

### **How It Works**

- If the battery has been at a stable and sufficient level for a certain period, the system considers enabling mining.
- Before switching on, it checks whether the expected solar production for the remainder of the day is high enough to sustain mining operations without excessive battery depletion.
- If both conditions are met, the miner is turned on and continues running until conditions require it to be shut down.

This approach ensures that mining only starts when there is a reasonable expectation of sustainable energy availability, preventing unnecessary battery drain.

### **2. Switching OFF the Miner**

The miner is turned off when solar production becomes insufficient to support its operation, and the battery level begins to decline beyond an acceptable threshold. This prevents excessive battery depletion and ensures energy is reserved for other essential uses.

### **How It Works**

- The system continuously monitors the battery level and solar production to determine whether mining can be sustained.
- When solar input drops significantly, signaling that the day’s productive hours are ending or conditions have changed, the automation evaluates whether the battery has enough remaining energy to continue operating.
- If the battery level falls below a dynamically set threshold—adjusted based on the solar energy forecast for the next day—the miner is shut down to conserve energy.

By adjusting the shutdown threshold dynamically according to solar forecasts, the system can optimize energy usage:

- On days with high expected solar production, it allows deeper battery discharge before shutting down.
- On days with lower expected solar production, it preserves more battery energy by shutting down sooner.

This logic ensures that mining is halted at the right time, balancing energy efficiency with the need to sustain battery reserves for non-mining power consumption.

---

## ✏️ Conclusion

Edge Mining proposes an innovative solution to optimize the use of excess energy produced by small power plants, particularly renewable ones. Integrating Bitcoin mining is a flexible, economically advantageous, and easy-to-implement choice. With our mining management system, users can maximize the efficiency of their plant, utilize the heat produced, and contribute positively to the Bitcoin network. This approach turns a potential inefficiency into a concrete opportunity for profit and sustainable energy use.

## 🤝 Contributions and Feedback

We welcome contributions and feedback to make this project even better. Feel free to open issues or submit pull requests.

Let’s mine smarter, together.

