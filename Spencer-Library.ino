#include <Arduino.h>
#include "src/Spencer.h"

void setup(){
	Serial.begin(115200);
	delay(100);  // let the USB-serial settle before any output
	Serial.println("Spencer booting...");
	Spencer.begin();
	Serial.println("Spencer.begin() returned");
}

void loop(){
	LoopManager::loop();
}