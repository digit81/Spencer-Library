#include "Spencer.h"
SpencerImpl Spencer;
LEDmatrixImpl LEDmatrix;
SpencerImpl::SpencerImpl()
{
}

SpencerImpl::~SpencerImpl()
{
}


void SpencerImpl::begin()
{
	Serial.println("[begin] disable WDT");
	disableCore0WDT();
	disableCore1WDT();

	Serial.println("[begin] init SPI");
	SPIClass spi(3);
	spi.begin(18, 19, 23, FLASH_CS_PIN);
	Serial.println("[begin] init SerialFlash");
	if(!SerialFlash.begin(spi, FLASH_CS_PIN)){
		Serial.println("Flash fail");
		return;
	}
	Serial.println("[begin] SerialFlash OK");

	pinMode(LED_PIN, OUTPUT);

	Serial.println("[begin] init LED matrix");
	if(!LEDmatrix.begin()){
		Serial.println("couldn't start matrix");
		for(;;);
	}
	Serial.println("[begin] LED matrix OK");

	Serial.println("[begin] init I2S");
	I2S* i2s = new I2S();
	i2s_driver_uninstall(I2S_NUM_0); //revert wrong i2s config from esp8266audio
	i2s->begin();
	Serial.println("[begin] I2S OK");

	Serial.println("[begin] init Playback/Recording");
	Playback.begin(i2s);
	Recording.begin(i2s);

	Serial.println("[begin] register listeners");
	LoopManager::addListener(&Playback);
	LoopManager::addListener(&LEDmatrix);
	LoopManager::addListener(new InputGPIO());

	Serial.println("[begin] set WiFi credentials");
	// DEV/LAB: hardcoded WiFi credentials for the Pi hotspot.
	// This bypasses any stored Settings values (which could be leftover
	// from previous firmware). Replace with Net.set(Settings.get().SSID,
	// Settings.get().pass) if you want to use the normal provisioning flow.
	Net.set("SpencerNet", "spencer123");

	Serial.println("[begin] set stack size");
	LoopManager::setStackSize(10240);

	Serial.println("[begin] done");
}

bool SpencerImpl::loadSettings(){
	bool firstTime = !Settings.begin() || Settings.get().SSID[0] == 0;

	if(firstTime){
		Settings.reset();
		Settings.get().brightnessLevel = Settings.get().volumeLevel = 1;
		Settings.store();
	}

	uint8_t brightnessLevelValues[3] = {5, 20, 100};
	float audioLevelValues[3] = {0.1, 0.4, 1.0};
	LEDmatrix.setBrightness(brightnessLevelValues[Settings.get().brightnessLevel]);
	Playback.setVolume(audioLevelValues[Settings.get().volumeLevel]);

	return firstTime;
}
