# Gateway Specification: Marine Mega-Gateway (Radxa NX5)

## 1. Core Compute Module
- **SoM:** Radxa NX5 (Rockchip RK3588S)
- **Form Factor:** 260-pin SODIMM
- **Logic Voltage (VCCIO):** 3.3V (Mandatory for peripheral compatibility). 
    - **Implementation:** Tie SODIMM pins 255, 257, and 259 to the local 3.3V rail.
- **Note:** VCCIO 3.3V is mandatory to match RP2040, KSZ9897, and USB2517 logic levels.

## 2. High-Speed Interface Mapping
- **PCIe Lane 1 (`combphy2_psu`):** M.2 E-Key Slot (WiFi/BT — e.g., Intel AX210).
    - **WiFi:** PCIe 2.1 x1.
    - **Bluetooth:** USB2 via USB2517 Hub #1 Port 1 (upstream: `u2phy2` / Host0).
      `u2phy1` / OTG1 is **not available** on RK3588S — it exists only on the full
      dual-GMAC RK3588 variant. Hub #1 Port 1 (formerly assigned to the Legacy
      E-Key Slot A) was re-allocated to carry the AX210 BT interface.
    - **Power Budget:** 5W Peak (3.3V @ 1.5A).
- **PCIe Lane 2 (`combphy0_ps`):** M.2 M-Key Slot (NVMe SSD).
    - **Performance:** PCIe 2.1 x1 (Theoretical 500MB/s, Real-world ~450MB/s).
    - **Power Budget:** 7W Peak (3.3V @ 2.1A).
- **USB 2.0 OTG (`u2phy0`):** M.2 B-Key Slot (4G/5G Cellular Modem).
    - **Constraint:** `combphy0_ps` is consumed by NVMe PCIe; `usbdp_phy0` is consumed by
      DisplayPort. Therefore OT.
    - **Throughput:** Max ~480 Mbps — sufficient for 4G LTE (~150 Mbps peak).
    - **Power Budget:** 8W Peak.

## 3. Reset GPIO Assignments
All four peripheral reset signals are grouped on GPIO bank 3 to minimise PCB routing distance.

| Signal | GPIO | DTS polarity | Connected to | Note |
|---|---|---|---|---|
| NVMe PERST# | GPIO3_B7 | `GPIO_ACTIVE_HIGH` | M.2 M-Key pin 22 | Direct, no inverter |
| WiFi PERST# | GPIO3_C0 | `GPIO_ACTIVE_HIGH` | M.2 E-Key pin 22 | Direct, no inverter |
| Hub #1 RESET# | GPIO3_C1 | `GPIO_ACTIVE_LOW` | USB2517 #1 RESET# pin | Pull-up on PCB |
| Hub #2 RESET# | GPIO3_C2 | `GPIO_ACTIVE_LOW` | USB2517 #2 RESET# pin | Pull-up on PCB |

**PCIe PERST# polarity note:** `GPIO_ACTIVE_HIGH` in the Device Tree does **not** require an
inverter. The RK3588S PCIe kernel driver asserts reset by writing logical 0 (→ GPIO LOW →
PERST# LOW = asserted) and releases it by writing logical 1 (→ GPIO HIGH → PERST# HIGH =
de-asserted). This matches the M.2 PERST# spec directly. The same convention is used by the
upstream Radxa NX5 IO reference board (`gpio3 RK_PD1 GPIO_ACTIVE_HIGH` for its PCIe slot).

**USB2517 RESET# pull-up:** The hub RESET# pin must be pulled high via a 10 kΩ resistor to
3.3V on the PCB so the hub comes out of reset automatically if the GPIO floats during early boot.

## 4. Networking & Switching
- **Controller:** Microchip KSZ9897 (7-Port Gigabit Switch).
- **Uplink:** RGMII to NX5 `gmac1` — the only GMAC on RK3588S.
    - **Trace Requirement:** Length-match all RGMII signals (125MHz) to within ±50 mils.
- **Downlink Ports:** 5× 10/100/1000 Mbps RJ45 using KSZ9897 internal PHYs (P1–P5, `port@0`–`port@4`). KSZ9897 P6 (`port@5`, MAC-only, no integrated PHY) is left unconnected on v1 hardware. A 6th copper port can be added later by wiring P6 RGMII to an external PHY (e.g. TI DP83867IRPAP).
- **Management:** Bit-bang I2C (`i2c-gpio` driver) on GPIO0_C3 (SCL) / GPIO0_C2 (SDA). Device address 0x5F, managed by the Linux DSA subsystem.
    - **Note:** GPIO0_C3/C2 are general-purpose GPIOs. The RK3588S hardware I2C7 M1 mux variant does not exist and is not used.

## 5. USB Expansion (12-Port Array)
- **Hub Controllers:** 2x Microchip USB2517 (7-Port Industrial Hubs).
- **Uplinks:** `u2phy2` (USB2 host0) → Hub #1; `u2phy3` (USB2 host1) → Hub #2.
- **Management:** Shared I2C Bus.
- **Hub #1 (Address 0x2C):** Port 1 → AX210 BT (Intel WiFi module Bluetooth USB2 interface); Ports 2-7 → 6x External USB2.
    - **Hub #2 (Address 0x2D):** Port 1 → VectorE M.2 E-Key (USB2); Ports 2-7 → 6x External USB2.
- **Hardware Configuration:** Address strapping via CFG_SEL0 (GND for 0x2C, 3.3V for 0x2D).
- **Total Capacity:** 12x External High-Speed 480Mbps ports.
- **Power Budget:** 30W Total (500mA per port @ 5V simultaneously).

## 6. Custom Modular I/O (M.2 E-Key)

- **Slot A (Legacy Serial Interface — NMEA 0183 & SeaTalk1):** M.2 **B-Key** slot. Interface is
  **UART-only** (no USB lines connected). `uart9` M2 (4-wire: TX/RX/RTS/CTS) provides the
  serial link. Card presence is detected by hardware GPIO: **GPIO3_D0** samples the W_DISABLE#
  line, which is pulled HIGH on the PCB; inserting a card shorts it LOW (active-low, 100 kΩ
  pull-up). No USB or software enumeration is used for card detection.
  - TX:  `GPIO3_D2 / UART9_TX_M2`  (SODIMM Pin 203)
  - RX:  `GPIO3_D1 / UART9_RX_M2`  (SODIMM Pin 205)
  - RTS: `GPIO3_D3 / UART9_RTSN_M2` (SODIMM Pin 207)
  - CTS: `GPIO3_C7 / UART9_CTSN_M2` (SODIMM Pin 209)
  - Card detect: `GPIO3_D0` (SODIMM Pin — W_DISABLE# active-low)
- **Slot B (VectorE Engine — GNSS, Motion & Environment):** M.2 **E-Key** slot. USB2 via
  Hub #2 Port 1. Card presence detected by USB enumeration on the hub downstream port.
- **Voltage:** Vio pins on M.2 slots driven by NX5 3.3V rail for automatic logic level matching.

## 7. Industrial Connectivity (NMEA2000)
- **Transceiver:** TI ISO1050DUBR (Galvanically Isolated CAN).
- **SoM Connection:** 
    - Pin 118 (CAN1_TX_M1 / GPIO1_A1) -> ISO1050 Pin 3 (TXD).
    - Pin 120 (CAN1_RX_M1 / GPIO1_A0) -> ISO1050 Pin 2 (RXD).
- **Isolation:** Maintain 5mm creepage barrier. Bus side (VCC2) powered by N2K network 5V.
- **Load Rating:** LEN = 1 (50mA draw from N2K bus).

## 8. PSU Supervisor Interface (RP2040/RP2350 Link)
This section defines the physical and logical handshake between the Radxa NX5 SoM and the RP2040-based PSU.

### 8.1 Power Control & Handshake
- **Pin 241 (PWR_ON#):** 
    - **Function:** Input to SoM. Momentary LOW pulse (500ms) triggers boot.
    - **Logic:** Pulled up to 1.8V inside SoM. **Must be driven via Open-Drain** by RP2040.
- **Pin 239 (PMIC_EXT_EN):**
    - **Function:** Output from SoM. High when the RK806 PMIC is active.
    - **Role:** RP2040 monitors this to enable the `5V_main` rail (Switch/Hubs/PoE).
- **Pin 237 (RESET#):**
    - **Function:** Input to SoM. Hard hardware reset.
    - **Role:** RP2040 pulls LOW only if a "System Hang" is detected via UART2.

### 8.2 Telemetry & Communication (Management I2C — bit-bang)
- **Pin 140 (GPIO0_C3):** SCL — bit-bang clock line for the shared management I2C bus.
- **Pin 142 (GPIO0_C2):** SDA — bit-bang data line for the shared management I2C bus.
- **Driver:** Linux `i2c-gpio` (bit-bang). The RK3588S hardware I2C7 M1 mux variant does not exist; GPIO0_C3/C2 are wired as general-purpose GPIO outputs.
- **Bus clients:** KSZ9897 (0x5F), USB2517 #1 (0x2C), USB2517 #2 (0x2D), RP2040 PSU supervisor (0x44).
- **Requirement:** 2.2 kΩ pull-ups to 3.3V on PCB.

### 8.3 System Monitoring (UART2)
- **Pin 123 (UART2_TX_M0 / GPIO0_B6):** NX5 Debug Output.
- **Pin 125 (UART2_RX_M0 / GPIO0_B5):** NX5 Debug Input.
- **Role:** RP2040 parses these logs for SCPI status updates and crash detection.

### 8.4 Critical Interrupts (Emergency)
- **Pin 121 (GPIO0_B4):** **Power_Fail_Interrupt (Input to NX5)**.
    - **Function:** RP2040 pulls this LOW immediately when DC input is lost.
    - **Software:** Triggers `systemd` power-off target in Linux.
- **Pin 119 (GPIO0_B3):** **Safe_To_Cut_Power (Output from NX5)**.
    - **Function:** NX5 drives this HIGH when the filesystem is unmounted and the kernel is halted.
    - **Role:** RP2040 waits for this signal before killing the `5V_always` rail.

## 9. Dual Display Interface
The Gateway supports two independent display outputs for multi-zone marine monitoring.

### 9.1 Primary Display: Chart Table (HDMI)
- **Interface:** Native HDMI 2.1 TX.
- **Resolution:** Supports up to 8K @ 60Hz.
- **SoM Connection:** Dedicated HDMI pins on SODIMM-260 (Pins 139-163 range).
- **Protection:** Requires ESD suppression (e.g., ESDALC6V1) near the physical connector.
- **Connector:** Standard HDMI Type-A.

### 9.2 Secondary Display: Cockpit (DisplayPort)
- **Interface:** Native DisplayPort 1.4 TX — **no onboard DP-to-HDMI bridge**.
- **Rationale:** Cockpit displays often use non-standard aspect ratios and resolutions
  (e.g., 1920×480 bar displays, 3840×1080 ultra-wide panels). A DP-to-HDMI active
  bridge restricts output to CEA-861 Video ID Codes and a fixed PLL table, making
  it incompatible with custom timings. Direct DP passes the display's full EDID to
  the RK3588S VOP2 scaler and generates any pixel clock the display requires.
- **Resolution:** Any resolution/timing supported by DP 1.4 (up to 4K @ 60Hz HBR3).
  Non-standard panels (e.g., 1920×480) are fully supported via EDID negotiation.
- **Signal Path:** Uses the RK3588S USB-DP combo PHY (`usbdp_phy0`) with all 4 lanes
  allocated to DisplayPort (`dp0 → vp2`). Does not conflict with USB 3.0 or PCIe lanes.
- **Connector:** Standard DisplayPort connector. If the cockpit display has only HDMI
  input, use an **external active DP→HDMI adapter/cable** — this preserves full
  timing flexibility while keeping the bridge off the PCB.

### 9.3 Display Management
- **OS Support:** Linux VOP2 driver (RK3588S); EDID read automatically at boot.
- **Configuration:** Dual-monitor "Extended Desktop" mode via `xrandr` or Wayland compositor.
- **Power:** HDMI controller powered by 5V_main rail; DP PHY powered by SoM 1.8V/0.9V internal supplies.

---

## 10. Physical Connection Reference

### 10.1 NX5 SODIMM (260-pin) — Carrier Board Connections

| SODIMM Pin | Signal / GPIO | Direction | Destination | Notes |
|---|---|---|---|---|
| 109 | USB0-DN / TYPEC0_OTG_DM | Bidir | M.2 B-Key (Cellular) | USB2 OTG0 D− |
| 111 | USB0-DP / TYPEC0_OTG_DP | Bidir | M.2 B-Key (Cellular) | USB2 OTG0 D+ |
| 115 | USB1-DN / USB20_HOST0_DM | Bidir | USB2517 #1 upstream | USB2 Host0 D− |
| 117 | USB1-DP / USB20_HOST0_DP | Bidir | USB2517 #1 upstream | USB2 Host0 D+ |
| 118 | GPIO1_A1 / CAN1_TX_M1 | Output | ISO1050 Pin 3 (TXD) | NMEA 2000 / CAN |
| 119 | GPIO0_B3 | Output | RP2040 input | Safe_To_Cut; driven HIGH at safe shutdown |
| 120 | GPIO1_A0 / CAN1_RX_M1 | Input | ISO1050 Pin 2 (RXD) | NMEA 2000 / CAN |
| 121 | GPIO0_B4 | Input | RP2040 open-drain | Power_Fail_INT; active-LOW |
| 121 | USB2-DN / USB20_HOST1_DM | Bidir | USB2517 #2 upstream | USB2 Host1 D− |
| 123 | GPIO0_B6 / UART2_TX_M0 | Output | RP2040 RX | Debug console; 115200 8N1 |
| 123 | USB2-DP / USB20_HOST1_DP | Bidir | USB2517 #2 upstream | USB2 Host1 D+ |
| 125 | GPIO0_B5 / UART2_RX_M0 | Input | RP2040 TX | Debug console |
| 131 | PCIE0-RX0N | Input | M.2 M-Key (NVMe) | PCIe x1 RX− lane 0 |
| 133 | PCIE0-RX0P | Input | M.2 M-Key (NVMe) | PCIe x1 RX+ lane 0 |
| 134 | PCIE0-TX0N | Output | M.2 M-Key (NVMe) | PCIe x1 TX− lane 0 |
| 136 | PCIE0-TX0P | Output | M.2 M-Key (NVMe) | PCIe x1 TX+ lane 0 |
| 140 | GPIO0_C3 / I2C SCL | Bidir | Management I2C bus | Bit-bang SCL; 2.2 kΩ pull-up on PCB |
| 142 | GPIO0_C2 / I2C SDA | Bidir | Management I2C bus | Bit-bang SDA; 2.2 kΩ pull-up on PCB |
| 160 | PCIE0-CLKN | Output | M.2 M-Key (NVMe) | PCIe refclk− |
| 162 | PCIE0-CLKP | Output | M.2 M-Key (NVMe) | PCIe refclk+ |
| 161 | USBSS-RXN | Input | M.2 E-Key (WiFi) | USB3 SS RX− (WiFi PCIe reuses combphy2) |
| 163 | USBSS-RXP | Input | M.2 E-Key (WiFi) | USB3 SS RX+ |
| 166 | USBSS-TXN | Output | M.2 E-Key (WiFi) | USB3 SS TX− |
| 168 | USBSS-TXP | Output | M.2 E-Key (WiFi) | USB3 SS TX+ |
| 167 | PCIE1-RX0N | Input | M.2 E-Key (WiFi) | PCIe x1 RX− (combphy2_psu) |
| 169 | PCIE1-RX0P | Input | M.2 E-Key (WiFi) | PCIe x1 RX+ |
| 172 | PCIE1-TX0N | Output | M.2 E-Key (WiFi) | PCIe x1 TX− |
| 174 | PCIE1-TX0P | Output | M.2 E-Key (WiFi) | PCIe x1 TX+ |
| 173 | PCIE1-CLKN | Output | M.2 E-Key (WiFi) | PCIe refclk− |
| 175 | PCIE1-CLKP | Output | M.2 E-Key (WiFi) | PCIe refclk+ |
| 179 | PCIE-WAKE | Input | M.2 E-Key (WiFi) | PCIe wake; active-LOW |
| 180 | PCIE0-CLKREQ | Input | M.2 M-Key (NVMe) | PCIe clock request; active-LOW |
| 181 | PCIE0-RST | Output | M.2 M-Key (NVMe) | PERST# = GPIO3_B7; active-LOW |
| 182 | PCIE1-CLKREQ | Input | M.2 E-Key (WiFi) | PCIe clock request; active-LOW |
| 183 | PCIE1-RST | Output | M.2 E-Key (WiFi) | PERST# = GPIO3_C0; active-LOW |
| 184 | GBE-MDI0N | Bidir | KSZ9897 port@6 | RGMII MDI pair 0− |
| 186 | GBE-MDI0P | Bidir | KSZ9897 port@6 | RGMII MDI pair 0+ |
| 188 | GBE-LED-LINK | Output | Status LED | Ethernet link indicator |
| 190 | GBE-MDI1N | Bidir | KSZ9897 port@6 | RGMII MDI pair 1− |
| 192 | GBE-MDI1P | Bidir | KSZ9897 port@6 | RGMII MDI pair 1+ |
| 194 | GBE-LED-ACT | Output | Status LED | Ethernet activity indicator |
| 196 | GBE-MDI2N | Bidir | KSZ9897 port@6 | RGMII MDI pair 2− |
| 198 | GBE-MDI2P | Bidir | KSZ9897 port@6 | RGMII MDI pair 2+ |
| 202 | GBE-MDI3N | Bidir | KSZ9897 port@6 | RGMII MDI pair 3− |
| 204 | GBE-MDI3P | Bidir | KSZ9897 port@6 | RGMII MDI pair 3+ |
| 206 | GPIO3_B7 / PCIE0-RST | Output | M.2 M-Key pin 22 | NVMe PERST#; active-LOW |
| 208 | GPIO3_C0 / PCIE1-RST | Output | M.2 E-Key pin 22 | WiFi PERST#; active-LOW |
| 212 | GPIO3_C1 | Output | USB2517 #1 RESET# | Hub reset; active-LOW; 10 kΩ pull-up on PCB |
| 218 | GPIO3_C2 | Output | USB2517 #2 RESET# | Hub reset; active-LOW; 10 kΩ pull-up on PCB |
| 236 | UART2-TXD | Output | RP2040 RX | Alt path for UART2_TX_M0 (same signal as pin 123) |
| 237 | RESET# | Input | RP2040 (open-drain) | Hard reset; RP2040 asserts on hang only |
| 238 | UART2-RXD | Input | RP2040 TX | Alt path for UART2_RX_M0 (same signal as pin 125) |
| 239 | PMIC_EXT_EN | Output | RP2040 monitor input | HIGH when RK806 PMIC active |
| 241 | PWR_ON# | Input | RP2040 (open-drain) | Momentary LOW boots SoM |
| 251, 252 | VIN | Supply in | 5V carrier rail | SoM input power |
| 253, 254 | VIN | Supply in | 5V carrier rail | SoM input power |
| 255, 256 | VIN / VCCIO | Supply in | 5V / 3.3V carrier rail | VIN + VCCIO |
| 257, 258 | VIN / VCCIO | Supply in | 5V / 3.3V carrier rail | VIN + VCCIO |
| 259, 260 | VIN / VCCIO | Supply in | 5V / 3.3V carrier rail | VIN + VCCIO; VCCIO mandatory 3.3V |
| 39 | DP0-TXD0N | Output | DisplayPort connector | DP lane 0− |
| 41 | DP0-TXD0P | Output | DisplayPort connector | DP lane 0+ |
| 45 | DP0-TXD1N | Output | DisplayPort connector | DP lane 1− |
| 47 | DP0-TXD1P | Output | DisplayPort connector | DP lane 1+ |
| 51 | DP0-TXD2N | Output | DisplayPort connector | DP lane 2− |
| 53 | DP0-TXD2P | Output | DisplayPort connector | DP lane 2+ |
| 57 | DP0-TXD3N | Output | DisplayPort connector | DP lane 3− |
| 59 | DP0-TXD3P | Output | DisplayPort connector | DP lane 3+ |
| 88 | DP0-HPD | Input | DisplayPort connector | Hot-plug detect |
| 90 | DP0-AUXN | Bidir | DisplayPort connector | AUX channel− |
| 92 | DP0-AUXP | Bidir | DisplayPort connector | AUX channel+ |
| 63 | HDMI-TX2N | Output | HDMI Type-A connector | HDMI TMDS lane 2− |
| 65 | HDMI-TX2P | Output | HDMI Type-A connector | HDMI TMDS lane 2+ |
| 69 | HDMI-TX1N | Output | HDMI Type-A connector | HDMI TMDS lane 1− |
| 71 | HDMI-TX1P | Output | HDMI Type-A connector | HDMI TMDS lane 1+ |
| 75 | HDMI-TX0N | Output | HDMI Type-A connector | HDMI TMDS lane 0− |
| 77 | HDMI-TX0P | Output | HDMI Type-A connector | HDMI TMDS lane 0+ |
| 81 | HDMI-TX3N | Output | HDMI Type-A connector | HDMI TMDS clock− |
| 83 | HDMI-TX3P | Output | HDMI Type-A connector | HDMI TMDS clock+ |
| 94 | HDMI-CEC | Bidir | HDMI Type-A connector | CEC control line |

> Pin numbers are from the Radxa NX5 V1.1 schematic (CONNECTOR page, U90043). GPIO3_B7/C0/C1/C2 confirmed on pins 206/208/212/218. Rows are sorted by pin number within each functional group; the table is not exhaustive — GND, NC, and unconnected pins are omitted.

---

### 10.2 M.2 M-Key Slot (NVMe SSD)

| M.2 Pin | Signal | Direction | Source | Notes |
|---|---|---|---|---|
| 22 | PERST# | Input | GPIO3_B7 (NX5) | Active-LOW; direct, no inverter |
| 41–52 | PCIe 2.1 x1 (TX/RX) | Bidir | combphy0_ps (NX5) | Data lanes |
| 1, 5, 6 | 3.3V | Supply in | vcc3v3_nvme rail | 7W peak budget |

---

### 10.3 M.2 E-Key Slot (WiFi/BT — e.g. Intel AX210)

| M.2 Pin | Signal | Direction | Source | Notes |
|---|---|---|---|---|
| 22 | PERST# | Input | GPIO3_C0 (NX5) | Active-LOW; direct, no inverter |
| 41–52 | PCIe 2.1 x1 (TX/RX) | Bidir | combphy2_psu (NX5) | WiFi data lanes |
| 33, 35 | USB2 D−/D+ | Bidir | USB2517 Hub #1 Port 1 (via u2phy2 / Host0) | Bluetooth interface; u2phy1/OTG1 does not exist on RK3588S |
| 1, 5, 6 | 3.3V | Supply in | vcc3v3_wifi rail | 5W peak budget |

---

### 10.4 M.2 B-Key Slot (4G/5G Cellular Modem)

| M.2 Pin | Signal | Direction | Source | Notes |
|---|---|---|---|---|
| 33, 35 | USB2 D−/D+ | Bidir | u2phy0 / OTG0 (NX5) | 480 Mbps only; no SS PHY |
| 2, 3 | 5V (VBUS) | Supply in | vcc_cellular rail | 8W peak budget |

---

### 10.5 M.2 B-Key Slot A (Legacy Serial Interface — NMEA 0183 & SeaTalk1)

This slot uses **UART only** (no USB lines connected). Hub #1 Port 1, formerly assigned here,
was re-allocated to carry the AX210 Bluetooth interface.

| M.2 / SODIMM Signal | GPIO | Direction | Notes |
|---|---|---|---|
| UART9_TX_M2 (Pin 203) | GPIO3_D2 | Output → card | Serial TX; 4-wire UART with HW flow control |
| UART9_RX_M2 (Pin 205) | GPIO3_D1 | Input ← card | Serial RX |
| UART9_RTSN_M2 (Pin 207) | GPIO3_D3 | Output → card | Request To Send |
| UART9_CTSN_M2 (Pin 209) | GPIO3_C7 | Input ← card | Clear To Send |
| W_DISABLE# / Card Detect (GPIO3_D0) | GPIO3_D0 | Input ← card | Active-LOW; 100 kΩ pull-up on PCB; LOW = card inserted |
| 3.3V (slot power) | — | Supply in | Carrier 3.3V rail; Slot Vio = 3.3V |

---

### 10.6 M.2 E-Key Slot B (VectorE Engine — GNSS, Motion & Environment)

| M.2 Pin | Signal | Direction | Source | Notes |
|---|---|---|---|---|
| 33, 35 | USB2 D−/D+ | Bidir | USB2517 #2 Port 1 | Card presence auto-detected by hub |
| 1, 4 | 3.3V | Supply in | Carrier 3.3V rail | Slot Vio = 3.3V (NX5 VCCIO) |

---

### 10.7 Microchip USB2517 Hub #1 (I2C 0x2C)

| Connection | Signal | Direction | Peer | Notes |
|---|---|---|---|---|
| Upstream | USB2 HS D−/D+ | Bidir | u2phy2 / Host0 (NX5) | Host controller input |
| RESET# | GPIO3_C1 | Input | NX5 | Active-LOW; 10 kΩ pull-up to 3.3V on PCB |
| I2C | SDA/SCL | Bidir | Management I2C bus | Address 0x2C; CFG_SEL0 = GND |
| Port 1 | USB2 HS D−/D+ | Bidir | AX210 BT (Intel WiFi module) | Bluetooth USB2 interface; re-allocated from Legacy Slot A |
| Ports 2–7 | USB2 HS D−/D+ | Bidir | 6× external USB2 connectors | |
| VDD | 3.3V | Supply in | Carrier 3.3V rail | |

---

### 10.8 Microchip USB2517 Hub #2 (I2C 0x2D)

| Connection | Signal | Direction | Peer | Notes |
|---|---|---|---|---|
| Upstream | USB2 HS D−/D+ | Bidir | u2phy3 / Host1 (NX5) | Host controller input |
| RESET# | GPIO3_C2 | Input | NX5 | Active-LOW; 10 kΩ pull-up to 3.3V on PCB |
| I2C | SDA/SCL | Bidir | Management I2C bus | Address 0x2D; CFG_SEL0 = 3.3V |
| Port 1 | USB2 HS D−/D+ | Bidir | M.2 E-Key Slot B | VectorE Engine upstream |
| Ports 2–7 | USB2 HS D−/D+ | Bidir | 6× external USB2 connectors | |
| VDD | 3.3V | Supply in | Carrier 3.3V rail | |

---

### 10.9 Microchip KSZ9897 Ethernet Switch (I2C 0x5F)

| Connection | Signal | Direction | Peer | Notes |
|---|---|---|---|---|
| port@6 / P7 (CPU) | RGMII 12-signal bus | Bidir | NX5 gmac1 | 1000BASE-T, RGMII-ID; length-matched ±50 mil |
| I2C | SDA/SCL | Bidir | Management I2C bus | Address 0x5F; DSA management |
| port@0 / P1 (lan1) | Integrated PHY | — | RJ45 #1 | 10/100/1000BASE-T, internal PHY |
| port@1 / P2 (lan2) | Integrated PHY | — | RJ45 #2 | 10/100/1000BASE-T, internal PHY |
| port@2 / P3 (lan3) | Integrated PHY | — | RJ45 #3 | 10/100/1000BASE-T, internal PHY |
| port@3 / P4 (lan4) | Integrated PHY | — | RJ45 #4 | 10/100/1000BASE-T, internal PHY |
| port@4 / P5 (lan5) | Integrated PHY | — | RJ45 #5 | 10/100/1000BASE-T, internal PHY |
| port@5 / P6 | MAC-only | — | *(unconnected — v1)* | Reserved for future 6th RJ45 via ext. PHY |
| VDD | 3.3V | Supply in | Carrier 3.3V rail | |
