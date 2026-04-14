#ifndef SPENCER_SETTINGS_H
#define SPENCER_SETTINGS_H

#include <Arduino.h>

struct SettingsData {
	// DEV/LAB: default WiFi points at the Pi hotspot. Note that
	// Spencer.cpp currently hardcodes these at the Net.set() call site
	// as well, so these defaults only matter if you revert that change.
	char SSID[64] = "SpencerNet";
	char pass[64] = "spencer123";
	bool fahrenheit = false;
	uint8_t brightnessLevel = 1; //medium brightness
	uint8_t volumeLevel = 1; //medium volume
	bool calibrated = false;
};

class SettingsImpl {
public:
	bool begin();

	void store();

	SettingsData& get();

	/**
	 * Resets the data (to zeroes). Doesn't store.
	 */
	void reset();

	uint getVersion(){
		return 2;
	}

private:
	SettingsData data;

};

extern SettingsImpl Settings;

#endif //SPENCER_SETTINGS_H
