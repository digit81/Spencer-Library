#include <Arduino.h>
#include "src/Spencer.h"

void setup(){
	Spencer.begin();
}

void loop(){
	LoopManager::loop();
}