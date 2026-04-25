# Tasmota Midea AC MQTT Web

# Midea AC / Kältebringer Climate Control via Tasmota Berry
Control of a **Kältebringer Split Air Conditioner** (Midea Protocol) using an **ESP32 with Tasmota** and Berry script. Communication via the internal UART port (USB-like socket) of the indoor unit.

## 👋 Note from First-Time Developer
This is my **first project** where I've used external sources and inspirations.  
If I've done anything wrong with licenses, attribution, or anything else, **please send me an email** and I'll fix it immediately.

## 📖 Background

Kältebringer air conditioners are based on the **Midea Protocol**, which is also used by
many other brands (Comfee, Inventor, Klarstein, Pioneer, etc.).
The indoor unit has a UART port (implemented as USB socket), normally for
WiFi dongle (e.g. SmartKit).

This project replaces the original dongle with an **ESP32 with Tasmota**,
controlling the AC locally without cloud.

### Origin of the Code

The project was developed **from scratch** based on:

- Documentation of [Midea UART Protocol](https://github.com/georgezhao2010/midea_ac_lan)
- Reverse engineering AC ↔ ESP32 communication  
- Adaptations for Kältebringer model specifics

Protocol findings differing from standard Midea docs:

| Property | Standard Midea | Kältebringer |
|---|---|---|
| Frame length | `byte[1]` = Total length | `byte[1]` = Total length **- 1** |
| Network handshake | Optional | **Required** (Type 0x63) |
| Room temperature | C0 body[11] | **A5 body[8] / 10.0** (more precise) |
| C0 body[11] heating | Room temp | **Heat exchanger temp** (>38°C) |
| Energy counter | Not documented | A5 body[16]*256 + body[17] (Wh) |

## 🔧 Hardware

### Required
- **ESP32-DevKit** (e.g. ESP32-WROOM-32)
- **USB-A plug** (AC connection)
- Tasmota Firmware (ESP32, v13.x+ Berry)

## Tested on: 
- ESP-WROOM-32 NodeMCU

## 🔌 Wiring
| Board-Aufdruck | GPIO | Funktion |
|---|---|---|
| RX2 | GPIO16 | Serial RX (Empfang von Klima) |
| TX2 | GPIO17 | Serial TX (Senden an Klima) |

Important: TX and RX must be crossed! ESP TX2 → AC RX.
Pin assignment USB socket of air conditioner

USB-A socket (viewed from front):
| Pin | Signal |
|---|---|
| 1 | +5V |
| 2 | TX |
| 3 | RX |
| 4 | GND |

**ESP32 GPIO:**
| Label | GPIO | Function |
|-------|------|----------|
| RX2   | 16   | Serial RX |
| TX2   | 17   | Serial TX |

## 📦 Installation

### 1. Flash Tasmota
ESP32 mit [Tasmota32](https://tasmota.github.io/install/)

### 2. Upload Berry script
**Console → Manage File System** → `midea_ac.be`

### 3. Autostart
Create `autoexec.be`:
```berry
load('midea_ac.be')
restart 1
````

### 4. Check console:
MID: Midea AC v5-fixed started
MID: * OFF Auto 24.0 Fan=Auto In=23.2 Out=15.0

## 📡 Commands
| Befehl     | Beispiel        | Beschreibung                 |
| ---------- | --------------- | ---------------------------- |
| MideaPower | MideaPower ON   | Ein/Aus/Toggle               |
| MideaMode  | MideaMode cool  | auto/cool/dry/heat/fan       |
| MideaTemp  | MideaTemp 24    | 16-30°C                      |
| MideaFan   | MideaFan auto   | auto/silent/low/medium/high  |
| MideaSwing | MideaSwing both | off/vertical/horizontal/both |
| MideaEco   | MideaEco ON     | Eco On/Off                   |
| MideaTurbo | MideaTurbo ON   | Turbo On/Off                 |

## HTTP:
```http
http://<IP>/cm?cmnd=MideaPower%20ON
````

### 📊 MQTT
```
Control: cmnd/<topic>/MideaPower → ON

Status: stat/<topic>/RESULT
````
## JSON
```JSON
{"MideaAC":{"Power":"ON","Mode":"Heat","TargetTemp":24.0,"IndoorTemp":23.2,"EnergyWh":812}}
````


