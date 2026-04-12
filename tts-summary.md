# TTS & Speech Recognition - Polish Language Support Summary

## Project Overview

Spencer-Library is an Arduino/ESP32 library for the **Spencer DIY voice assistant** by CircuitMess. It uses cloud-based services for both text-to-speech (TTS) and speech-to-intent (STI) via a CircuitMess backend server.

---

## Text-to-Speech (TTS)

### Current Configuration

- **File:** `src/Speech/TextToSpeech.cpp` (lines 68-78)
- **Endpoint:** `https://spencer.circuitmess.com:8443/tts/v1/text:synthesize`
- **Language:** `en-US` (hardcoded)
- **Voice:** `en-US-Standard-D` (hardcoded)
- **Gender:** `NEUTRAL`
- **Format:** MP3, 16 kHz, speaking rate 0.96, pitch 5.5

### How to Change TTS to Polish

The language is hardcoded in a JSON request pattern in `TextToSpeech.cpp` at line 68. Change the following values:

```cpp
// BEFORE (English)
"'languageCode': 'en-US',"
"'name': 'en-US-Standard-D',"

// AFTER (Polish)
"'languageCode': 'pl-PL',"
"'name': 'pl-PL-Standard-A',"
```

Available Polish voices (Google Cloud TTS naming convention):
| Voice Name | Gender |
|---|---|
| `pl-PL-Standard-A` | Female |
| `pl-PL-Standard-B` | Male |
| `pl-PL-Standard-C` | Male |
| `pl-PL-Standard-D` | Female |
| `pl-PL-Standard-E` | Female |
| `pl-PL-Wavenet-A` | Female |
| `pl-PL-Wavenet-B` | Male |
| `pl-PL-Wavenet-C` | Male |
| `pl-PL-Wavenet-D` | Female |
| `pl-PL-Wavenet-E` | Female |

### TTS Feasibility: LIKELY POSSIBLE (client-side change)

The API pattern matches Google Cloud TTS. If the CircuitMess backend proxies to Google Cloud TTS, Polish is a supported Google language and should work with just the client-side code change above. However, this depends on the server not restricting language options.

### TTS Constraints

- Max text length: 130 characters
- Max simultaneous samples: 4
- Requires active internet connection

---

## Speech Recognition (Speech-to-Intent / STI)

### Current Configuration

- **File:** `src/Speech/SpeechToIntent.cpp`
- **Endpoint:** `https://spencer.circuitmess.com:8443/sti/speech`
- **Input:** Raw WAV audio (16-bit PCM, mono, 16 kHz)
- **Output:** JSON with `text` (transcript), `intents` (with confidence), and `entities` (slot/value pairs)
- **Language:** No language parameter is sent in the request - the server decides

### How to Change Speech Recognition to Polish

**This is NOT a simple client-side change.** The STI client code (`SpeechToIntent.cpp`) sends only raw audio to the server with a `Content-Type: audio/wav` header. There is **no language parameter** in the HTTP request.

The speech recognition language is controlled entirely server-side. To support Polish you would need:

1. **Server-side language support** - The CircuitMess STI server must support Polish speech recognition. It likely uses a service like Wit.ai or Google Speech-to-Text under the hood.
2. **NLU model for Polish** - The intent recognition (NLU) component must be trained with Polish intents and entities. Spencer uses intents like weather queries, jokes, time, etc. - these would all need Polish training data.
3. **A language header or parameter** - The client would need to send a language hint (e.g., `Accept-Language: pl-PL` header) and the server would need to honor it.

### Possible Client-Side Attempt

You could try adding a language header to the STI request in `SpeechToIntent.cpp` around line 65:

```cpp
http.addHeader("Content-Type", "audio/wav");
http.addHeader("Accept-Language", "pl-PL");  // Add this line
```

But this will only work if the server recognizes and handles this header, which is unlikely without server-side changes.

### STI Feasibility: UNLIKELY WITHOUT SERVER CHANGES

The speech recognition and intent parsing are fully server-controlled. Without modifications to the CircuitMess backend, Polish speech recognition is not achievable from client code alone.

---

## Settings Storage

- **File:** `src/Settings.h`
- **Current struct:** Stores WiFi credentials, temperature unit, brightness, volume, and calibration flag
- **No language field exists** - A language preference field would need to be added to `SettingsData` to persist the user's choice

### Suggested Settings Addition

```cpp
struct SettingsData {
    char SSID[64] = {0};
    char pass[64] = {0};
    bool fahrenheit = false;
    uint8_t brightnessLevel = 1;
    uint8_t volumeLevel = 1;
    bool calibrated = false;
    char language[6] = "en-US";  // NEW: language code for TTS/STI
};
```

---

## Summary Table

| Feature | Polish Support | Change Required | Difficulty |
|---|---|---|---|
| **TTS (Text-to-Speech)** | Likely possible | Client-side: change `languageCode` and `name` in `TextToSpeech.cpp` | Low |
| **Speech Recognition (STI)** | Not possible without server changes | Server-side: add Polish ASR + NLU model | High |
| **Language Persistence** | Not implemented | Add `language` field to `SettingsData` in `Settings.h` | Low |
