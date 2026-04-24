#- midea_ac.be v5-fixed - Basis v4 + sichere Fixes -#

import string

var TX_PIN = 16
var RX_PIN = 17
var POLL_S = 15

var CRC_TBL = bytes("005EBCE2613FDD83C29C7E20A3FD1F419DC3217FFCA2401E5F01E3BD3E6082DC237D9FC1421CFEA0E1BF5D0380DE3C62BEE0025CDF81633D7C22C09E1D43A1FF4618FAA427799BC584DA3866E5BB5907DB856739BAE406581947A5FB7826C49A653BD987045AB8E6A7F91B45C6987A24F8A6441A99C7257B3A6486D85B05E7B98CD2306EEDB3510F4E10F2AC2F7193CD114FADF3702ECC92D38D6F31B2EC0E50AFF1134DCE90722C6D33D18F0C52B0EE326C8ED0530DEFB1F0AE4C1291CF2D73CA947628ABF517490856B4EA6937D58B5709EBB536688AD495CB2977F4AA4816E9B7550B88D6346A2B7597C94A14F6A8742AC896154BA9F7B6E80A54D7896B35")

class MideaAC
  var ser
  var buf
  var msg_id
  var net_ok
  var poll_cnt

  var power
  var mode
  var target_temp
  var fan_speed
  var swing_v
  var swing_h
  var eco
  var turbo
  var beeper
  var indoor_temp
  var outdoor_temp
  var power_w
  var energy_wh

  def init()
    self.ser = serial(RX_PIN, TX_PIN, 9600)
    self.buf = bytes()
    self.msg_id = 1
    self.net_ok = false
    self.poll_cnt = 0
    self.power       = false
    self.mode        = 0
    self.target_temp = 24.0
    self.fan_speed   = 102
    self.swing_v     = false
    self.swing_h     = false
    self.eco         = false
    self.turbo       = false
    self.beeper      = true
    self.indoor_temp = 0.0
    self.outdoor_temp= 0.0
    self.power_w     = 0
    self.energy_wh   = 0

    tasmota.add_driver(self)
    tasmota.add_cmd('MideaPower',
      / cmd, idx, p, j -> self.cmd_power(p))
    tasmota.add_cmd('MideaMode',
      / cmd, idx, p, j -> self.cmd_mode(p))
    tasmota.add_cmd('MideaTemp',
      / cmd, idx, p, j -> self.cmd_temp(p))
    tasmota.add_cmd('MideaFan',
      / cmd, idx, p, j -> self.cmd_fan(p))
    tasmota.add_cmd('MideaSwing',
      / cmd, idx, p, j -> self.cmd_swing(p))
    tasmota.add_cmd('MideaEco',
      / cmd, idx, p, j -> self.cmd_eco(p))
    tasmota.add_cmd('MideaTurbo',
      / cmd, idx, p, j -> self.cmd_turbo(p))
    tasmota.add_cmd('MideaBeeper',
      / cmd, idx, p, j -> self.cmd_beeper(p))
    tasmota.add_cmd('MideaQuery',
      / cmd, idx, p, j -> self.cmd_query())
    # KEIN Startup-Timer! Warten auf 0x63 Ping
    print("MID: Midea AC v5-fixed gestartet")
  end

  # ═══════ CRC8 ═══════════════════════════════
  def crc8(data)
    var crc = 0
    for i : 0 .. size(data) - 1
      crc = CRC_TBL[(crc ^ data[i]) & 0xFF]
    end
    return crc
  end

  # ═══════ Frame senden ═══════════════════════
  def send_frame(ftype, body)
    var blen = size(body)
    var flen = 10 + blen + 2
    var f = bytes(flen)
    f.resize(flen)
    f[0] = 0xAA
    f[1] = flen - 1
    f[2] = 0xAC
    f[8] = self.msg_id
    self.msg_id = (self.msg_id + 1) & 0xFF
    f[9] = ftype
    for i : 0 .. blen - 1
      f[10 + i] = body[i]
    end
    f[flen - 2] = self.crc8(body)
    var s = 0
    for i : 1 .. flen - 2
      s = s + f[i]
    end
    f[flen - 1] = (256 - (s & 0xFF)) & 0xFF
    self.ser.write(f)
  end

  def send_net()
    var b = bytes(19)
    b.resize(19)
    b[0] = 0x02
    b[4] = 0x04
    b[5] = 192
    b[6] = 168
    b[7] = 1
    b[8] = 1
    self.send_frame(0x63, b)
    self.net_ok = true
  end

  def send_query()
    self.send_frame(0x03,
      bytes("418100FF03FF00020000000000000000000000000000"))
  end

  # ═══════ SET-Befehl ═════════════════════════
  def send_set()
    var b = bytes(
      "0000000000000000000000000000000000000000000000")
    b[0] = 0x40
    var b1 = 0x00
    if self.power  b1 = b1 | 0x01  end
    b1 = b1 | ((self.mode & 0x07) << 5)
    b[1] = b1
    var ti = int(self.target_temp)
    var b2 = (ti - 16) & 0x0F
    if (self.target_temp - ti) >= 0.5
      b2 = b2 | 0x10
    end
    b[2] = b2
    b[3] = self.fan_speed & 0xFF
    b[4] = 0x7F
    b[5] = 0x7F
    var sw = 0x00
    if self.swing_v  sw = sw | 0x0C  end
    if self.swing_h  sw = sw | 0x03  end
    b[7] = sw
    if self.turbo  b[8] = 0x20  end
    if self.eco    b[9] = 0x80  end
    if self.beeper b[10] = 0x42  end
    self.send_frame(0x02, b)
    tasmota.set_timer(2000,
      / -> self.send_query())
  end

  # ═══════ Empfang (1:1 aus v4!) ══════════════
  def every_100ms()
    if self.ser.available() <= 0  return  end
    self.buf = self.buf + self.ser.read()
    while size(self.buf) >= 2
      if self.buf[0] != 0xAA
        var found = false
        for i : 1 .. size(self.buf) - 1
          if self.buf[i] == 0xAA
            self.buf = self.buf[
              i .. size(self.buf) - 1]
            found = true
            break
          end
        end
        if !found
          self.buf = bytes()
          return
        end
      end
      if size(self.buf) < 2  return  end
      var flen = self.buf[1] + 1
      if flen < 10 || flen > 200
        self.buf = self.buf[
          1 .. size(self.buf) - 1]
        continue
      end
      if size(self.buf) < flen  return  end
      var frame = self.buf[0 .. flen - 1]
      if flen < size(self.buf)
        self.buf = self.buf[
          flen .. size(self.buf) - 1]
      else
        self.buf = bytes()
      end
      var s = 0
      for i : 1 .. flen - 2
        s = s + frame[i]
      end
      if ((256 - (s & 0xFF)) & 0xFF) != frame[flen - 1]
        continue
      end
      if flen <= 12  continue  end
      var body = frame[10 .. flen - 3]
      var ft = frame[9]
      if ft == 0x63
        self.send_net()
        if !self.net_ok
          tasmota.set_timer(1500,
            / -> self.send_query())
        end
      elif ft == 0x03 || ft == 0x02
        self.parse_c0(body)
      elif ft == 0x04 || ft == 0x05
        self.parse_notify(body)
      end
    end
  end

  # ═══════ C0 Status parsen (v4 + Fixes) ══════
  def parse_c0(body)
    if size(body) < 13
      print("MID: Body zu kurz: "
        + str(size(body)))
      return
    end
    if body[0] != 0xC0 && body[0] != 0xC1
      return
    end

    self.power = (body[1] & 0x01) != 0
    self.mode = (body[1] >> 5) & 0x07

    # FIX: Leistung auf 0 wenn AUS
    if !self.power
      self.power_w = 0
    end

    self.target_temp = ((body[2] & 0x0F) + 16) * 1.0
    if (body[2] & 0x10) != 0
      self.target_temp = self.target_temp + 0.5
    end

    self.fan_speed = body[3] & 0x7F

    if size(body) > 7
      self.swing_v = (body[7] & 0x0C) != 0
      self.swing_h = (body[7] & 0x03) != 0
    end
    if size(body) > 8
      self.turbo = (body[8] & 0x20) != 0
    end
    if size(body) > 9
      self.eco = (body[9] & 0x80) != 0
    end

    # FIX: Innentemp nur als Fallback wenn
    # A5 noch nichts geliefert hat
    if size(body) > 11 && body[11] != 0xFF
      var t = (body[11] - 50) / 2.0
      if self.indoor_temp == 0.0
        if t > 0 && t < 38
          self.indoor_temp = t
          print(string.format(
            "MID: C0 Innen=%.1f (Fallback)", t))
        end
      end
    end

    if size(body) > 12 && body[12] != 0xFF
      var ot = (body[12] - 50) / 2.0
      if ot > -30 && ot < 55
        self.outdoor_temp = ot
      end
    end

    print(string.format(
      "MID: * %s %s %.1f Fan=%s In=%.1f Out=%.1f",
      self.power ? "ON" : "OFF",
      self.mode_s(), self.target_temp,
      self.fan_s(),
      self.indoor_temp, self.outdoor_temp))

    self.pub_stat()
  end

  # ═══════ Notify parsen (v4-Basis + Fixes) ═══
  def parse_notify(body)
    if size(body) < 2  return  end

    if body[0] == 0xA5 && size(body) > 17

      # FIX: Raumtemp aus b[8]/10 (genauer!)
      if size(body) > 8 && body[8] > 0
        var rt = body[8] / 10.0
        if rt > 5 && rt < 45
          self.indoor_temp = rt
          print(string.format(
            "MID: A5 RT=%.1f", rt))
        end
      end

      # FIX: Energiezaehler (Wh kumuliert)
      self.energy_wh = body[16] * 256 + body[17]

      # Debug
      print(string.format(
        "MID: A5 Energie=%dWh b[7]=%d b[8]=%d",
        self.energy_wh, body[7], body[8]))

      # Waermetauscher Debug
      if size(body) > 23 && body[23] != 0
        print(string.format(
          "MID: A5 WT=%.1f",
          (body[23] - 50) / 2.0))
      end

    elif body[0] == 0xA0
      print("MID: A0")
    elif body[0] == 0xA1
      print("MID: A1")
    elif body[0] == 0xA2
      print("MID: A2")
    elif body[0] == 0xA3
      print("MID: A3")
    elif body[0] == 0xA6
      print("MID: A6")
    end
  end

  # ═══════ MQTT publishen ═════════════════════
  def pub_stat()
    tasmota.publish_result(string.format(
      "{\"MideaAC\":{\"Power\":\"%s\","
      "\"Mode\":\"%s\",\"TargetTemp\":%.1f,"
      "\"IndoorTemp\":%.1f,"
      "\"OutdoorTemp\":%.1f,"
      "\"Fan\":\"%s\",\"SwingV\":\"%s\","
      "\"SwingH\":\"%s\",\"Eco\":\"%s\","
      "\"Turbo\":\"%s\","
      "\"EnergyWh\":%d}}",
      self.power ? "ON" : "OFF",
      self.mode_s(), self.target_temp,
      self.indoor_temp, self.outdoor_temp,
      self.fan_s(),
      self.swing_v ? "ON" : "OFF",
      self.swing_h ? "ON" : "OFF",
      self.eco ? "ON" : "OFF",
      self.turbo ? "ON" : "OFF",
      self.energy_wh), "RESULT")
  end

  # ═══════ Polling (1:1 aus v4!) ══════════════
  def every_second()
    self.poll_cnt = self.poll_cnt + 1
    if self.poll_cnt >= POLL_S && self.net_ok
      self.poll_cnt = 0
      self.send_query()
    end
  end

  # ═══════ MQTT Telemetrie ════════════════════
  def json_append()
    tasmota.response_append(string.format(
      ",\"MideaAC\":{\"Power\":\"%s\","
      "\"Mode\":\"%s\",\"TargetTemp\":%.1f,"
      "\"IndoorTemp\":%.1f,"
      "\"OutdoorTemp\":%.1f,"
      "\"Fan\":\"%s\",\"SwingV\":\"%s\","
      "\"SwingH\":\"%s\",\"Eco\":\"%s\","
      "\"Turbo\":\"%s\","
      "\"EnergyWh\":%d}",
      self.power ? "ON" : "OFF",
      self.mode_s(), self.target_temp,
      self.indoor_temp, self.outdoor_temp,
      self.fan_s(),
      self.swing_v ? "ON" : "OFF",
      self.swing_h ? "ON" : "OFF",
      self.eco ? "ON" : "OFF",
      self.turbo ? "ON" : "OFF",
      self.energy_wh))
  end

  # ═══════ Web: Istwerte ══════════════════════
  def web_sensor()
    var pw = self.power ? "🟢 AN" : "🔴 AUS"
    tasmota.web_send_decimal(string.format(
      "{s}Klima{m}%s{e}", pw))
    tasmota.web_send_decimal(string.format(
      "{s}Modus{m}%s{e}", self.mode_s()))
    tasmota.web_send_decimal(string.format(
      "{s}Soll{m}%.1f °C{e}",
      self.target_temp))
    tasmota.web_send_decimal(string.format(
      "{s}Innen{m}%.1f °C{e}",
      self.indoor_temp))
    tasmota.web_send_decimal(string.format(
      "{s}Aussen{m}%.1f °C{e}",
      self.outdoor_temp))
    tasmota.web_send_decimal(string.format(
      "{s}Luefter{m}%s{e}", self.fan_s()))
    var sw = "Aus"
    if self.swing_v && self.swing_h
      sw = "Beide"
    elif self.swing_v
      sw = "Vertikal"
    elif self.swing_h
      sw = "Horizontal"
    end
    tasmota.web_send_decimal(string.format(
      "{s}Swing{m}%s{e}", sw))
    tasmota.web_send_decimal(string.format(
      "{s}Eco{m}%s{e}",
      self.eco ? "AN" : "AUS"))
    tasmota.web_send_decimal(string.format(
      "{s}Turbo{m}%s{e}",
      self.turbo ? "AN" : "AUS"))
    if self.energy_wh > 0
      tasmota.web_send_decimal(string.format(
        "{s}Energie{m}%d Wh{e}",
        self.energy_wh))
    end
  end

  # ═══════ Hilfsfunktionen ════════════════════
  def mode_s()
    if   self.mode == 1  return "Auto"
    elif self.mode == 2  return "Cool"
    elif self.mode == 3  return "Dry"
    elif self.mode == 4  return "Heat"
    elif self.mode == 5  return "Fan"
    end
    return "Auto"
  end

  def fan_s()
    if   self.fan_speed >= 100  return "Auto"
    elif self.fan_speed <= 20   return "Silent"
    elif self.fan_speed <= 40   return "Low"
    elif self.fan_speed <= 60   return "Medium"
    elif self.fan_speed <= 80   return "High"
    end
    return str(self.fan_speed)
  end

  # ═══════ Befehle ════════════════════════════
  def cmd_power(p)
    var v = string.toupper(
      string.tr(str(p), " ", ""))
    if v == "ON" || v == "1" || v == "TRUE"
      self.power = true
    elif v == "OFF" || v == "0" || v == "FALSE"
      self.power = false
    elif v == "TOGGLE" || v == "2"
      self.power = !self.power
    end
    self.send_set()
    tasmota.resp_cmnd(string.format(
      "{\"MideaPower\":\"%s\"}",
      self.power ? "ON" : "OFF"))
  end

  def cmd_mode(p)
    var v = string.tolower(
      string.tr(str(p), " ", ""))
    if   v == "auto" || v == "1"  self.mode = 1
    elif v == "cool" || v == "2"  self.mode = 2
    elif v == "dry"  || v == "3"  self.mode = 3
    elif v == "heat" || v == "4"  self.mode = 4
    elif v == "fan"  || v == "5"  self.mode = 5
    end
    self.power = true
    self.send_set()
    tasmota.resp_cmnd(string.format(
      "{\"MideaMode\":\"%s\"}",
      self.mode_s()))
  end

  def cmd_temp(p)
    self.target_temp = real(str(p))
    if self.target_temp < 16
      self.target_temp = 16.0
    end
    if self.target_temp > 30
      self.target_temp = 30.0
    end
    self.target_temp = int(
      self.target_temp * 2) / 2.0
    self.send_set()
    tasmota.resp_cmnd(string.format(
      "{\"MideaTemp\":%.1f}",
      self.target_temp))
  end

  def cmd_fan(p)
    var v = string.tolower(
      string.tr(str(p), " ", ""))
    if   v == "auto"    self.fan_speed = 102
    elif v == "silent"  self.fan_speed = 20
    elif v == "low"     self.fan_speed = 40
    elif v == "medium"  self.fan_speed = 60
    elif v == "high"    self.fan_speed = 80
    end
    self.send_set()
    tasmota.resp_cmnd(string.format(
      "{\"MideaFan\":\"%s\"}",
      self.fan_s()))
  end

  def cmd_swing(p)
    var v = string.tolower(
      string.tr(str(p), " ", ""))
    self.swing_v = false
    self.swing_h = false
    if   v == "vertical" || v == "v"
      self.swing_v = true
    elif v == "horizontal" || v == "h"
      self.swing_h = true
    elif v == "both" || v == "on"
      self.swing_v = true
      self.swing_h = true
    end
    self.send_set()
    tasmota.resp_cmnd_done()
  end

  def cmd_eco(p)
    var v = string.toupper(
      string.tr(str(p), " ", ""))
    self.eco = (v == "ON" || v == "1")
    if self.eco  self.turbo = false  end
    self.send_set()
    tasmota.resp_cmnd(string.format(
      "{\"MideaEco\":\"%s\"}",
      self.eco ? "ON" : "OFF"))
  end

  def cmd_turbo(p)
    var v = string.toupper(
      string.tr(str(p), " ", ""))
    self.turbo = (v == "ON" || v == "1")
    if self.turbo  self.eco = false  end
    self.send_set()
    tasmota.resp_cmnd(string.format(
      "{\"MideaTurbo\":\"%s\"}",
      self.turbo ? "ON" : "OFF"))
  end

  def cmd_beeper(p)
    var v = string.toupper(
      string.tr(str(p), " ", ""))
    self.beeper = (v == "ON" || v == "1")
    tasmota.resp_cmnd(string.format(
      "{\"MideaBeeper\":\"%s\"}",
      self.beeper ? "ON" : "OFF"))
  end

  def cmd_query()
    self.send_query()
    tasmota.resp_cmnd_done()
  end
end

var midea_ac = MideaAC()