-- Honeycomb Bravo Plugin Script version v1.1.1
-- Based on HoneycombBravoHelper for Linux https://gitlab.com/honeycomb-xplane-linux from Daniel Peukert
-- License:		GNU GPLv3

-- ***** Change Log *****
-- 0.0.4:	Modified from the original HoneycombBravoMacHelper v0.0.3 from Joe Milligan.
--		Modified for ZIBO B738.
-- 0.0.5:	Merged with the HoneycombBravoZIBOv1.5 from Alfiepops.
-- 0.0.6:	Fixed compatibility issues with X-Plane version XP12.0.9-rc-5 or newer.
-- 0.0.7:	Fixed Parking Brake LED and Anti Ice LED, matching the annunciators.
-- 0.0.8:	Added automatic airplane detection and set configuration.
--		Added ZIBO B738 profile.
--		Added BE9L profile.
--		Added default aircrafts profile.
--		Added Bravo and aircraft detection to the log.txt.
-- 0.0.9:	Fixed issue with LEDs not turning on.
--		Code clean up.
--		Typos fixed.
-- 0.0.10:	Fixed VS above 1000 fps for B738.
-- 1.0.0:	Initial public version.
-- 1.1.0:	Add C172 SKYHAWK profile, by Plam55.
--		Code clean up.
-- 1.1.1:	Fixed issue with C172 G1000 Autopilot Altitude knob function.
--		Add SR22 profile, by Plam55

local bravo = hid_open(10571, 6401)

function write_log(message)
	logMsg(os.date('%H:%M:%S ') .. '[Honeycomb Bravo v1.1.1]: ' .. message)
end

if bravo == nil then
	write_log('ERROR No Honeycomb Bravo Throttle Quadrant detected. Script stopped.')
	return
else
	write_log('INFO Honeycomb Bravo Throttle Quadrant detected.')
end

write_log('INFO Aircraft identified as ' .. PLANE_ICAO .. ' with filename ' .. AIRCRAFT_FILENAME)

-- Plugin Profile: a profile represents using aircraft-specific datarefs
local PROFILE = "default"

-- Switches for specific plugin behavior that transcends profiles
local SHOW_ANC_HYD = true
local ONLY_USE_AUTOPILOT_STATE = false
local NUM_ENGINES = 0

if PLANE_ICAO == "B738" then
	-- Laminar B738 / Zibo B738
	PROFILE = "B738"
elseif PLANE_ICAO == "C750" then
	-- Laminar Citation X
	PROFILE = "laminar/CitX"
elseif PLANE_ICAO == "B752" or PLANE_ICAO == "B753" then
	-- FlightFactor 757
	PROFILE = "FF/757"
elseif PLANE_ICAO == "B763" or PLANE_ICAO == "B764" then
	-- FlightFactor 767
	PROFILE = "FF/767"
elseif PLANE_ICAO == "C172" and AIRCRAFT_FILENAME == "Cessna_172SP.acf" then
	-- Laminar C172
	PROFILE = "laminar/C172"
elseif PLANE_ICAO == "A319" or PLANE_ICAO == "A20N"  or PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" then
	-- Toliss A32x
	PROFILE = "Toliss/32x"
	NUM_ENGINES = 2
	if PLANE_ICAO == "A346" then
		NUM_ENGINES = 4
	end
end

if PLANE_ICAO == "C172" or PLANE_ICAO == "SR22" then
	SHOW_ANC_HYD = false
	ONLY_USE_AUTOPILOT_STATE = true -- as the normal hdg and nav datarefs indicate hdg when they shouldn't
end

-- Disable the hydraulics annunciator on SEL aircraft, see https://forums.x-plane.org/index.php?/files/file/89635-honeycomb-bravo-plugin/&do=findComment&comment=396048
if
PLANE_ICAO == "C172" or 
PLANE_ICAO == "SR22" or 
PLANE_ICAO == "SR20" or
PLANE_ICAO == "S22T" or
PLANE_ICAO == "SR22T" or
PLANE_ICAO == "P28A" or
PLANE_ICAO == "C208" or
PLANE_ICAO == "K100" or
PLANE_ICAO == "KODI" or
PLANE_ICAO == "DA40" or
PLANE_ICAO == "RV10" or
false then
	SHOW_ANC_HYD = false
end

write_log('INFO Using aircraft profile: ' .. PROFILE)


local bitwise = require 'bit'

-- Helper functions
function int_to_bool(value)
	if value == 0 then
		return false
	else
		return true
	end
end

function get_ap_state(array)
	if array[0] >= 1 then
		return true
	else
		return false
	end
end

function array_has_true(array)
	for i = 0, 7 do
		if array[i] == 1 then
			return true
		end
	end

	return false
end

function array_has_positives(array)
	for i = 0, 7 do
		if array[i] > 0.01 then
			return true
		end
	end

	return false
end

-- LED definitions
local LED = {
	FCU_HDG =			{1, 1},
	FCU_NAV =			{1, 2},
	FCU_APR =			{1, 3},
	FCU_REV =			{1, 4},
	FCU_ALT =			{1, 5},
	FCU_VS =			{1, 6},
	FCU_IAS =			{1, 7},
	FCU_AP =			{1, 8},
	LDG_L_GREEN =		{2, 1},
	LDG_L_RED =			{2, 2},
	LDG_N_GREEN =		{2, 3},
	LDG_N_RED =			{2, 4},
	LDG_R_GREEN =		{2, 5},
	LDG_R_RED =			{2, 6},
	ANC_MSTR_WARNG =	{2, 7},
	ANC_ENG_FIRE =		{2, 8},
	ANC_OIL =			{3, 1},
	ANC_FUEL =			{3, 2},
	ANC_ANTI_ICE =		{3, 3},
	ANC_STARTER =		{3, 4},
	ANC_APU =			{3, 5},
	ANC_MSTR_CTN =		{3, 6},
	ANC_VACUUM =		{3, 7},
	ANC_HYD =			{3, 8},
	ANC_AUX_FUEL =		{4, 1},
	ANC_PRK_BRK =		{4, 2},
	ANC_VOLTS =			{4, 3},
	ANC_DOOR =			{4, 4},
}

-- Support variables & functions for sending LED data via HID

	local buffer = {}

	local master_state = false
	local buffer_modified = false

	function get_led(led)
		return buffer[led[1]][led[2]]
	end

	function set_led(led, state)
		if state ~= get_led(led) then
			buffer[led[1]][led[2]] = state
			buffer_modified = true
		end
	end

	function all_leds_off()
		for bank = 1, 4 do
			buffer[bank] = {}
			for bit = 1, 8 do
				buffer[bank][bit] = false
			end
		end

		buffer_modified = true
	end

	function send_hid_data()
		local data = {}

		for bank = 1, 4 do
			data[bank] = 0

			for bit = 1, 8 do
				if buffer[bank][bit] == true then
					data[bank] = bitwise.bor(data[bank], bitwise.lshift(1, bit - 1))
				end
			end
		end

		local bytes_written = hid_send_filled_feature_report(bravo, 0, 65, data[1], data[2], data[3], data[4]) -- 65 = 1 byte (report ID) + 64 bytes (data)

		if bytes_written == -1 then
			write_log('ERROR Feature report write failed, an error occurred')
		elseif bytes_written < 65 then
			write_log('ERROR Feature report write failed, only '..bytes_written..' bytes written')
		else
			buffer_modified = false
		end
	end

	-- Initialize our default state
	all_leds_off()
	send_hid_data()
	hid_open(10571, 6401) -- MacOS Bravo must be reopened for .joy axes to operate

	-- Change LEDs when their underlying dataref changes
	-- Bus voltage as a master LED switch
	local bus_voltage = dataref_table('sim/cockpit2/electrical/bus_volts')
	if PROFILE == "laminar/CitX" then
		-- On the C750 bus_volts is only on when the Standby Power is on, but the lights and indicators in the sim are on before that
		bus_voltage = dataref_table('laminar/CitX/APU/DC_volts')
	elseif PROFILE == "B738" then
		bus_voltage = dataref_table('laminar/B738/electric/batbus_status')
	end

    -- Datarefs configuration for Default Aircrafts.

	-- Autopilot
	local hdg = dataref_table('sim/cockpit2/autopilot/heading_mode')
	local nav = dataref_table('sim/cockpit2/autopilot/nav_status')
	local apr = dataref_table('sim/cockpit2/autopilot/approach_status')
	local rev = dataref_table('sim/cockpit2/autopilot/backcourse_status')
	local alt = dataref_table('sim/cockpit2/autopilot/altitude_hold_status')
	local vs = dataref_table('sim/cockpit2/autopilot/vvi_status')
	local ias = dataref_table('sim/cockpit2/autopilot/autothrottle_on')

	local ap = dataref_table('sim/cockpit2/autopilot/servos_on')
	local autopilot_state = dataref_table("sim/cockpit/autopilot/autopilot_state") -- see https://developer.x-plane.com/article/accessing-the-x-plane-autopilot-from-datarefs/
	if PROFILE == "B738" then
		hdg = dataref_table('laminar/B738/autopilot/hdg_sel_status')
		nav = dataref_table('laminar/B738/autopilot/lnav_status')
		apr = dataref_table('laminar/B738/autopilot/app_status')
		rev = dataref_table('laminar/B738/autopilot/vnav_status1')
		alt = dataref_table('laminar/B738/autopilot/alt_hld_status')
		vs = dataref_table('laminar/B738/autopilot/vs_status')
		ias = dataref_table('laminar/B738/autopilot/speed_status1')
		ap = dataref_table('laminar/B738/autopilot/cmd_a_status')
	elseif PROFILE == "Toliss/32x" then
		hdg = dataref_table('AirbusFBW/APLateralMode') -- 101
		nav = dataref_table('AirbusFBW/APLateralMode') -- 1
		apr = dataref_table('AirbusFBW/APPRilluminated')
		rev = dataref_table('AirbusFBW/ENGRevArray')
		alt = dataref_table('AirbusFBW/ALTmanaged') -- 101
		vs = dataref_table('AirbusFBW/APVerticalMode') --107
		ias = dataref_table('AirbusFBW/SPDmanaged')
		ap1 = dataref_table('AirbusFBW/AP1Engage')
		ap2 = dataref_table('AirbusFBW/AP2Engage')
	end


	-- Landing gear LEDs
	local gear = dataref_table('sim/flightmodel2/gear/deploy_ratio')
	local retractable_gear = dataref_table('sim/aircraft/gear/acf_gear_retract')

	-- Annunciator panel - top row
	local master_warn = dataref_table('sim/cockpit2/annunciators/master_warning')
	local fire = dataref_table('sim/cockpit2/annunciators/engine_fires')
	local oil_low_p = dataref_table('sim/cockpit2/annunciators/oil_pressure_low')
	local fuel_low_p = dataref_table('sim/cockpit2/annunciators/fuel_pressure_low')
	local anti_ice = dataref_table('sim/cockpit2/annunciators/pitot_heat')
	local anti_ice_flip = false
	local starter = dataref_table('sim/cockpit2/engine/actuators/starter_hit')
	local apu = dataref_table('sim/cockpit2/electrical/APU_running')
	if PROFILE == "B738" then
		fire = dataref_table('laminar/B738/annunciator/six_pack_fire')
		fuel_low_p = dataref_table('laminar/B738/annunciator/six_pack_fuel')
		anti_ice = dataref_table('laminar/B738/annunciator/six_pack_ice')
	elseif PROFILE == "FF/757" or PROFILE == "FF/767" then
		master_warn = dataref_table('inst/loopwarning')
		fire = dataref_table('sim/cockpit/warnings/annunciators/engine_fires')
		anti_ice = dataref_table('sim/cockpit2/ice/ice_window_heat_on')
		anti_ice_flip = true
	elseif PROFILE == "Toliss/32x" then
		master_warn = dataref_table('AirbusFBW/MasterWarn')
		apu_fire = dataref_table('AirbusFBW/OHPLightsATA26')
		eng_fire = dataref_table('AirbusFBW/OHPLightsATA70')
		oil_low_p = dataref_table('AirbusFBW/ENGOilPressArray')
		fuel_low_p = dataref_table('AirbusFBW/ENGFuelFlowArray')
		anti_ice = dataref_table('AirbusFBW/OHPLightsATA30')
		starter = dataref_table('AirbusFBW/StartValveArray')
		apu = dataref_table('AirbusFBW/APUAvail')
	end

	-- Annunciator panel - bottom row
	local master_caution = dataref_table('sim/cockpit2/annunciators/master_caution')
	local vacuum = dataref_table('sim/cockpit2/annunciators/low_vacuum')
	local hydro_low_p = dataref_table('sim/cockpit2/annunciators/hydraulic_pressure')
	local aux_fuel_pump_l = dataref_table('sim/cockpit2/fuel/transfer_pump_left')
	local aux_fuel_pump_r = dataref_table('sim/cockpit2/fuel/transfer_pump_right')
	local parking_brake = dataref_table('sim/cockpit2/controls/parking_brake_ratio')
	local volt_low = dataref_table('sim/cockpit2/annunciators/low_voltage')
	local canopy = dataref_table('sim/flightmodel2/misc/canopy_open_ratio')
	local doors = dataref_table('sim/flightmodel2/misc/door_open_ratio')
	local doors_array = {}
	local cabin_door = dataref_table('sim/cockpit2/annunciators/cabin_door_open')
	if PROFILE == "B738" then
		master_caution = dataref_table('laminar/B738/annunciator/master_caution_light')
		hydro_low_p = dataref_table('laminar/B738/annunciator/six_pack_hyd')
		parking_brake = dataref_table('laminar/B738/annunciator/parking_brake')
		doors = dataref_table('laminar/B738/annunciator/six_pack_doors')
		cabin_door = dataref_table('laminar/B738/toggle_switch/flt_dk_door')
	elseif PROFILE == "FF/757" then
		master_caution = dataref_table('inst/warning')
		doors_array[0] = dataref_table('anim/door/FL')
		doors_array[1] = dataref_table('anim/door/FR')
		doors_array[2] = dataref_table('anim/door/ML')
		doors_array[3] = dataref_table('anim/door/MR')
		doors_array[4] = dataref_table('anim/door/BL')
		doors_array[5] = dataref_table('anim/door/BR')
		doors_array[6] = dataref_table('1-sim/anim/doors/cargoBack/anim')
		doors_array[7] = dataref_table('1-sim/anim/doors/cargoSide/anim')
		doors_array[8] = dataref_table('anim/doorC') -- 757 freighter cargo door
		volt_low = dataref_table('sim/cockpit2/electrical/bus_volts')
	elseif PROFILE == "FF/767" then
		master_caution = dataref_table('sim/cockpit/warnings/annunciators/master_caution')
		doors_array[0] = dataref_table('1-sim/anim/doors/FL/anim')
		doors_array[1] = dataref_table('1-sim/anim/doors/FR/anim')
		doors_array[2] = dataref_table('1-sim/anim/doors/BL/anim')
		doors_array[3] = dataref_table('1-sim/anim/doors/BR/anim')
		doors_array[4] = dataref_table('1-sim/anim/doors/cargoFront/anim')
		doors_array[5] = dataref_table('1-sim/anim/doors/cargoBack/anim')
		doors_array[6] = dataref_table('1-sim/anim/doors/cargoSide/anim')
		volt_low = dataref_table('sim/cockpit2/electrical/bus_volts')
	elseif PROFILE == "Toliss/32x" then
		master_caution = dataref_table('AirbusFBW/MasterCaut')
		vacuum = dataref_table('sim/cockpit/misc/vacuum')
		hydro_low_p = dataref_table('AirbusFBW/HydSysPressArray')
		-- aux_fuel_pump_l = dataref_table('sim/cockpit/switches/fuel_pump_l')
		-- aux_fuel_pump_r = dataref_table('sim/cockpit/switches/fuel_pump_r')
		parking_brake = dataref_table('AirbusFBW/ParkBrake')
		volt_low = dataref_table('sim/cockpit2/electrical/battery_amps')
		-- canopy = dataref_table('sim/cockpit/switches/canopy_open')
		-- doors = dataref_table('sim/cockpit/switches/door_open')
		cabin_door = dataref_table('AirbusFBW/PaxDoorArray')
		doors_array[0] = dataref_table('AirbusFBW/PaxDoorArray')
		doors_array[1] = dataref_table('AirbusFBW/CargoDoorArray')
		doors_array[2] = dataref_table('AirbusFBW/BulkDoor')
	end

	local DOOR_LAST_FLASHING = -1
	local DOOR_LAST_STATE = true

	function handle_led_changes()
		if bus_voltage[0] > 0 then
			master_state = true

			-- HDG & NAV
			if bitwise.band(autopilot_state[0], 2) > 0 then
				-- Heading Select Engage
				set_led(LED.FCU_HDG, true)
				set_led(LED.FCU_NAV, false)
			elseif bitwise.band(autopilot_state[0], 512) > 0 or bitwise.band(autopilot_state[0], 524288) > 0 then
				-- Nav Engaged or GPSS Engaged
				set_led(LED.FCU_HDG, false)
				set_led(LED.FCU_NAV, true)
			elseif ONLY_USE_AUTOPILOT_STATE then
				-- Aircraft known to use autopilot_state
				set_led(LED.FCU_HDG, false)
				set_led(LED.FCU_NAV, false)
			else
				if PROFILE == "Toliss/32x" then
					if int_to_bool(ap1[0]) or int_to_bool(ap2[0]) then
						if hdg[0] == 101 then
							set_led(LED.FCU_HDG, true)
							set_led(LED.FCU_NAV, false)
						else 
							set_led(LED.FCU_HDG, false)
							set_led(LED.FCU_NAV, true)
						end
					else
						set_led(LED.FCU_HDG, false)
						set_led(LED.FCU_NAV, false)
					end
				else
					-- HDG
					set_led(LED.FCU_HDG, get_ap_state(hdg))

					-- NAV
					set_led(LED.FCU_NAV, get_ap_state(nav))		
				end
			end

			-- APR
			set_led(LED.FCU_APR, get_ap_state(apr))

			-- REV
			set_led(LED.FCU_REV, get_ap_state(rev))

			-- ALT
			local alt_bool

			if alt[0] > 1 then
				alt_bool = true
			else
				alt_bool = false
			end

			if PROFILE == "Toliss/32x" then
				if alt[0] == 0 or (not int_to_bool(ap1[0]) and not int_to_bool(ap2[0])) then
					set_led(LED.FCU_ALT, false)
				else
					set_led(LED.FCU_ALT, true)
				end
			else 
				set_led(LED.FCU_ALT, alt_bool)
			end

			-- VS
			if PROFILE == "Toliss/32x" then
				if vs[0] == 107 and (int_to_bool(ap1[0]) or int_to_bool(ap2[0])) then
					set_led(LED.FCU_VS, true)
				else
					set_led(LED.FCU_VS, false)
				end
			else 
				set_led(LED.FCU_VS, get_ap_state(vs))
			end

			-- IAS
			if bitwise.band(autopilot_state[0], 8) > 0 then
				-- Speed-by-pitch Engage AKA Flight Level Change
				-- See "Aliasing of Flight-Level Change With Speed Change" on https://developer.x-plane.com/article/accessing-the-x-plane-autopilot-from-datarefs/
				set_led(LED.FCU_IAS, true)
			else
				set_led(LED.FCU_IAS, get_ap_state(ias))
			end

			-- AUTOPILOT
			if PROFILE == "Toliss/32x" then
				set_led(LED.FCU_AP, int_to_bool(ap1[0]) or int_to_bool(ap2[0]))
			else
				set_led(LED.FCU_AP, int_to_bool(ap[0]))
			end

			-- Landing gear
			local gear_leds = {}

			for i = 1, 3 do
				gear_leds[i] = {nil, nil} -- green, red

				if retractable_gear[0] == 0 then
					-- No retractable landing gear
				else
					if gear[i - 1] == 0 then
						-- Gear stowed
						gear_leds[i][1] = false
						gear_leds[i][2] = false
					elseif gear[i - 1] == 1 then
						-- Gear deployed
						gear_leds[i][1] = true
						gear_leds[i][2] = false
					else
						-- Gear moving
						gear_leds[i][1] = false
						gear_leds[i][2] = true
					end
				end
			end

			set_led(LED.LDG_N_GREEN, gear_leds[1][1])
			set_led(LED.LDG_N_RED, gear_leds[1][2])
			set_led(LED.LDG_L_GREEN, gear_leds[2][1])
			set_led(LED.LDG_L_RED, gear_leds[2][2])
			set_led(LED.LDG_R_GREEN, gear_leds[3][1])
			set_led(LED.LDG_R_RED, gear_leds[3][2])

			-- MASTER WARNING
			set_led(LED.ANC_MSTR_WARNG, int_to_bool(master_warn[0]))

			-- ENGINE/APU FIRE 
			if PROFILE == 'Toliss/32x' then

				my_fire = false
				if apu_fire[20]>0 then
					my_fire = true
				end 
				for i = 11, 17 do
					if i == 11 or i==13 or i == 15 or i==17 then
						if eng_fire[i]~=nil and eng_fire[i] > 0 then
							my_fire = true
							break
						end
					end
				end
				set_led(LED.ANC_ENG_FIRE, my_fire)
			else
				set_led(LED.ANC_ENG_FIRE, array_has_true(fire))
			end

			-- LOW OIL PRESSURE
			if PROFILE == "Toliss/32x" then
				low_oil_light = false
				for i = 0, NUM_ENGINES-1 do
					if oil_low_p[i]~=nil and oil_low_p[i] < 0.075 then
						low_oil_light = true
						break
					end
				end
				set_led(LED.ANC_OIL, low_oil_light)
			else
				set_led(LED.ANC_OIL, array_has_true(oil_low_p))
			end

			-- LOW FUEL PRESSURE
			if PROFILE == "Toliss/32x" then
				low_fuel_light = false
				for i = 0, NUM_ENGINES-1 do
					if fuel_low_p[i]~=nil and fuel_low_p[i] < 0.075 then
						low_fuel_light = true
						break
					end
				end
				set_led(LED.ANC_FUEL, low_fuel_light)
			else
				set_led(LED.ANC_FUEL, array_has_true(fuel_low_p))
			end

			-- ANTI ICE
			if PROFILE == "Toliss/32x" then
				if array_has_positives(anti_ice) then
					set_led(LED.ANC_ANTI_ICE, true)
				else
					set_led(LED.ANC_ANTI_ICE, false)
				end
			else
				if not anti_ice_flip then
					set_led(LED.ANC_ANTI_ICE, int_to_bool(anti_ice[0]))
				else
					set_led(LED.ANC_ANTI_ICE, not int_to_bool(anti_ice[0]))
				end
			end

			-- STARTER ENGAGED
			set_led(LED.ANC_STARTER, array_has_true(starter))

			-- APU
			set_led(LED.ANC_APU, int_to_bool(apu[0]))

			-- MASTER CAUTION
			set_led(LED.ANC_MSTR_CTN, int_to_bool(master_caution[0]))

			-- VACUUM
			if PROFILE == "Toliss/32x" then
				if vacuum[0] < 1 then
					set_led(LED.ANC_VACUUM, true)
				else
					set_led(LED.ANC_VACUUM, false)
				end
			else
				set_led(LED.ANC_VACUUM, int_to_bool(vacuum[0]))
			end
			
			-- LOW HYD PRESSURE
			if PROFILE == "Toliss/32x" then
				low_hyd_light = true
				for i = 0, 2 do
					if hydro_low_p[i] > 2500 then
						low_hyd_light = false
						break
					end
				end
				set_led(LED.ANC_HYD, low_hyd_light)
			else
				if SHOW_ANC_HYD then
					set_led(LED.ANC_HYD, int_to_bool(hydro_low_p[0]))
				else
					-- For planes that don't have a hydraulic pressure annunciator
					set_led(LED.ANC_HYD, false)
				end
			end

			-- AUX FUEL PUMP
			local aux_fuel_pump_bool

			if aux_fuel_pump_l[0] == 2 or aux_fuel_pump_r[0] == 2 then
				aux_fuel_pump_bool = true
			else
				aux_fuel_pump_bool = false
			end

			set_led(LED.ANC_AUX_FUEL, aux_fuel_pump_bool)

			-- PARKING BRAKE
			local parking_brake_bool

			if parking_brake[0] > 0 then
				parking_brake_bool = true
			else
				parking_brake_bool = false
			end

			set_led(LED.ANC_PRK_BRK, parking_brake_bool)

			-- LOW VOLTS
			if PROFILE == "Toliss/32x" then
				if volt_low[0] < 0 then
					set_led(LED.ANC_VOLTS, true)
				else
					set_led(LED.ANC_VOLTS, false)
				end
			elseif PROFILE == "FF/757" then
				if volt_low[0] < 28 then
					set_led(LED.ANC_VOLTS, true)
				else
					set_led(LED.ANC_VOLTS, false)
				end
			elseif PROFILE == "FF/767" then
				if volt_low[0] < 25 then
					set_led(LED.ANC_VOLTS, true)
				else
					set_led(LED.ANC_VOLTS, false)
				end
			else
				set_led(LED.ANC_VOLTS, int_to_bool(volt_low[0]))
			end

			-- DOOR
			local door_bool = false

			if canopy[0] > 0.01 then
				door_bool = true
			end

			if door_bool == false then
				for i = 0, 9 do
					if doors[i] > 0.01 then
						door_bool = true
						break
					end
				end
			end

			if door_bool == false then
				for i = 0, 9 do
					if PROFILE == "Toliss/32x" and i == 0 then
						-- special case handling for aft cargo door (toliss/32x)
						if doors_array[i] ~= nil and array_has_positives(doors_array[i]) then
							door_bool = true
							break
						end
					else
						if doors_array[i] ~= nil and doors_array[i][0] > 0.01 then
							door_bool = true
							break
						end
					end
				end
			end

			if door_bool == false then
				door_bool = int_to_bool(cabin_door[0])
			end

			if cabin_door[0]>0.01 and cabin_door[0]<0.99 then
				set_led(LED.ANC_DOOR, DOOR_LAST_STATE)
				if os.clock()*1000 - DOOR_LAST_FLASHING > 200 then
					DOOR_LAST_STATE = not DOOR_LAST_STATE
					DOOR_LAST_FLASHING = os.clock()*1000
				end
			else
				set_led(LED.ANC_DOOR, door_bool)
			end

			
		elseif master_state == true then
			-- No bus voltage, disable all LEDs
			master_state = false
			all_leds_off()
		end

		-- If we have any LED changes, send them to the device
		if buffer_modified == true then
			send_hid_data()
		end
	end

	do_every_frame('handle_led_changes()')

	function exit_handler()
		all_leds_off()
		send_hid_data()
	end

	do_on_exit('exit_handler()')

-- Register commands for switching autopilot modes used by the rotary encoder
local mode = 'IAS'

function setMode(modeString)
	mode = modeString
end

create_command(
	'HoneycombBravo/mode_ias',
	'Set autopilot rotary encoder mode to IAS.',
	'setMode("IAS")',
	'',
	''
)

create_command(
	'HoneycombBravo/mode_crs',
	'Set autopilot rotary encoder mode to CRS.',
	'setMode("CRS")',
	'',
	''
)

create_command(
	'HoneycombBravo/mode_hdg',
	'Set autopilot rotary encoder mode to HDG.',
	'setMode("HDG")',
	'',
	''
)

create_command(
	'HoneycombBravo/mode_vs',
	'Set autopilot rotary encoder mode to VS.',
	'setMode("VS")',
	'',
	''
)

create_command(
	'HoneycombBravo/mode_alt',
	'Set autopilot rotary encoder mode to ALT.',
	'setMode("ALT")',
	'',
	''
)

-- Commands for changing values of the selected autopilot mode with the rotary encoder for Default Aircrafts.
local airspeed_is_mach = dataref_table('sim/cockpit2/autopilot/airspeed_is_mach')
local airspeed = dataref_table('sim/cockpit2/autopilot/airspeed_dial_kts_mach')
local course = dataref_table('sim/cockpit2/radios/actuators/nav1_obs_deg_mag_pilot')
local heading = dataref_table('sim/cockpit2/autopilot/heading_dial_deg_mag_pilot')
local vs = dataref_table('sim/cockpit2/autopilot/vvi_dial_fpm')
local altitude = dataref_table('sim/cockpit2/autopilot/altitude_dial_ft')

-- Acceleration parameters
local last_mode = mode
local last_time = os.clock() - 10 -- arbitrarily in the past

local number_of_turns = 0
local factor = 1
local fast_threshold = 5 -- number of turns in 1 os.clock() interval to engage 'fast' mode
local fast_ias = 2
local fast_crs = 5
local fast_hdg = 5
local fast_vs = 1
local fast_alt = 10

local vs_multiple = 50
local alt_multiple = 100

if PROFILE == "laminar/C172" then
	altitude = dataref_table('sim/cockpit/autopilot/current_altitude')

	-- 20ft at a time and no acceleration factor to match simulated flight control
	alt_multiple = 20
	fast_alt = 1
elseif PROFILE == "B738" then
	airspeed_is_mach = dataref_table('laminar/B738/autopilot/mcp_speed_dial_kts_mach')
	airspeed = dataref_table('laminar/B738/autopilot/mcp_speed_dial_kts')
	course = dataref_table('laminar/B738/autopilot/course_pilot')
	heading = dataref_table('laminar/B738/autopilot/mcp_hdg_dial')
	altitude = dataref_table('laminar/B738/autopilot/mcp_alt_dial')
	vs_multiple = 100
elseif PROFILE == "FF/757" or PROFILE == "FF/767" then
	airspeed = dataref_table('757Avionics/ap/spd_act')
	course = dataref_table('sim/cockpit/radios/nav2_obs_degm') -- nav2 targets ILS rather than VOR on nav1
	heading = dataref_table('757Avionics/ap/hdg_act')
	vs = dataref_table('757Avionics/ap/vs_act')
	altitude = dataref_table('757Avionics/ap/alt_act')
	vs_multiple = 100
end

function change_value(increase)
	local sign
	local vs_string
	local alt_string
	
	if increase == true then
		sign = 1
	else
		sign = -1
	end
	
	if mode == last_mode and os.clock() < last_time + 1 then
		number_of_turns = number_of_turns + 1
	else	
		number_of_turns = 0
		factor = 1
	end
	
	if number_of_turns > fast_threshold then
		if mode == 'IAS' then
			factor = fast_ias
		elseif mode == 'CRS' then
			factor = fast_crs
		elseif mode == 'HDG' then
			factor = fast_hdg
		elseif mode == 'VS' then
			factor = fast_vs
		elseif mode == 'ALT' then
			factor = fast_alt
		else
			factor = 1
		end
	else
		factor = 1
	end	

	if mode == 'IAS' then
		if airspeed_is_mach[0] == 1 then
			-- Float math is not precise, so we have to round the result
			airspeed[0] = math.max(0, (math.floor((airspeed[0] * 100) + 0.5) + (sign * factor)) / 100) -- changed for kts in else below, have not tested this yet
		else
			airspeed[0] = math.max(0, (math.floor(airspeed[0]) + (sign * factor)))
		end
	elseif mode == 'CRS' then
		if course[0] == 0 and sign == -1 then
			course[0] = 359
		else
			course[0] = (course[0] + (sign * factor)) % 360
		end
	elseif mode == 'HDG' then
		if heading[0] == 0 and sign == -1 then
			heading[0] = 359
		else
			heading[0] = (heading[0] + (sign * factor)) % 360
		end
	elseif mode == 'VS' then
		vs[0] = math.floor((vs[0] / vs_multiple) + (sign * factor)) * vs_multiple
	elseif mode == 'ALT' then
		altitude[0] = math.max(0, math.floor((altitude[0] / alt_multiple) + (sign * factor)) * alt_multiple)
	end
	last_mode = mode
	last_time = os.clock()
end

create_command(
	'HoneycombBravo/increase',
	'Increase the value of the autopilot mode selected with the rotary encoder.',
	'change_value(true)',
	'',
	''
)

create_command(
	'HoneycombBravo/decrease',
	'Decrease the value of the autopilot mode selected with the rotary encoder.',
	'change_value(false)',
	'',
	''
)

-- Register commands for keeping thrust reversers (all or separate engines) on while the commands are active
local reversers = dataref_table('sim/cockpit2/engine/actuators/prop_mode')

function get_prop_mode(state)
	if state == true then
		return 3
	else
		return 1
	end
end

function reversers_all(state)
	for i = 0, 7 do
		reversers[i] = get_prop_mode(state)
	end
end

function reverser(engine, state)
	reversers[engine - 1] = get_prop_mode(state)
end

create_command(
	'HoneycombBravo/thrust_reversers',
	'Hold all thrust reversers on.',
	'reversers_all(true)',
	'',
	'reversers_all(false)'
)

for i = 1, 8 do
	create_command(
		'HoneycombBravo/thrust_reverser_'..i,
		'Hold thrust reverser #'..i..' on.',
		'reverser('..i..', true)',
		'',
		'reverser('..i..', false)'
	)
end
