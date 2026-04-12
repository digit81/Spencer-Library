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

## Redirecting to Your Own Server

### What to change in the client code

Three modifications are needed in the Spencer firmware:

#### 1. Server URLs

| File | Line | Current URL |
|---|---|---|
| `src/Speech/TextToSpeech.cpp` | 86 | `https://spencer.circuitmess.com:8443/tts/v1/text:synthesize` |
| `src/Speech/SpeechToIntent.cpp` | 61 | `https://spencer.circuitmess.com:8443/sti/speech` |

Change both URLs to point to your server, e.g. `https://myserver.local:8443/tts/v1/text:synthesize`.

#### 2. SSL Certificate Fingerprint

Both files define `#define CA` with a SHA256 certificate fingerprint for TLS pinning. Replace with your server's certificate fingerprint:

```cpp
// In both TextToSpeech.cpp and SpeechToIntent.cpp
#define CA "YOUR:SERVER:CERT:SHA256:FINGERPRINT:HERE"
```

Get your cert fingerprint with:
```bash
openssl x509 -in your_cert.pem -fingerprint -sha256 -noout
```

#### 3. Language code in TTS pattern

In `TextToSpeech.cpp` line 70-71, change `en-US` to `pl-PL` (see section above).

---

## API Specification for Your Server

### TTS Endpoint: `POST /tts/v1/text:synthesize`

**Request:**
```
Content-Type: application/json; charset=utf-8
Accept-Encoding: identity
```
```json
{
  "input": { "text": "Cześć, jak się masz?" },
  "voice": {
    "languageCode": "pl-PL",
    "name": "pl-PL-Standard-A",
    "ssmlGender": "NEUTRAL"
  },
  "audioConfig": {
    "audioEncoding": "MP3",
    "speakingRate": 0.96,
    "pitch": 5.5,
    "sampleRateHertz": 16000
  }
}
```

**Response** (HTTP 200):
```json
{
  "audioContent": "<base64-encoded MP3 data>"
}
```

**Notes:**
- The client uses a streaming character-by-character JSON parser (NOT a full JSON library) - it scans for the `"audioContent"` key and base64-decodes the value directly to flash storage
- Output MUST be MP3, 16 kHz
- The request uses single-quoted JSON (non-standard) but your server should accept it
- Keep the response simple - only the `audioContent` field is read

### STI Endpoint: `POST /sti/speech`

**Request:**
```
Content-Type: audio/wav
Accept-Encoding: identity
Content-Length: <size in bytes>
Body: raw WAV file (16-bit PCM, mono, 16000 Hz, compressed)
```

**Response** (HTTP 200):
```json
{
  "text": "jaka jest pogoda w Warszawie",
  "intents": [
    {
      "name": "weather",
      "confidence": 0.95
    }
  ],
  "entities": {
    "location": [
      {
        "name": "city",
        "body": "Warszawa"
      }
    ]
  }
}
```

**Critical constraints:**
- JSON buffer on ESP32 is small: `JSON_ARRAY_SIZE(2) + JSON_OBJECT_SIZE(50) + 200` (~450 bytes). Keep responses compact!
- The `text` field is required (client checks `containsKey("text")`)
- `intents` array: each entry needs `name` (string) and `confidence` (float)
- `entities` object: each key maps to an array of objects with `name` and `body` fields
- If no intent is detected, you can omit `intents` or return an empty array - the client will set `error = INTENT`

---

## Open-Source Polish Language Tools for Your Server

### Speech-to-Text (ASR) - Polish Support

| Tool | Polish Support | Quality | Notes |
|---|---|---|---|
| **OpenAI Whisper** | Excellent | High | Best option. Supports 99 languages including Polish. Models: tiny to large. Self-hostable. `pip install openai-whisper`. Use `whisper --language pl` |
| **Vosk** | Yes | Good | Lightweight, offline. Polish model available at `vosk-model-small-pl-0.22` (~50MB) and `vosk-model-pl-0.22` (~1GB). Fast on CPU. Great for ESP32-class audio |
| **Whisper.cpp** | Excellent | High | C++ port of Whisper. Lower resource usage than Python Whisper. Same Polish quality |
| **wav2vec2 (HuggingFace)** | Yes | Good | `jonatasgrosman/wav2vec2-large-xlsr-53-polish` and other community models on HuggingFace |
| **Kaldi** | Yes | Good | Polish models exist but complex setup. Better alternatives exist now |
| **Mozilla DeepSpeech** | Limited | Fair | Community Polish models exist but project is archived. Not recommended |
| **Coqui STT** | Limited | Fair | Fork of DeepSpeech. Some Polish community models. Project winding down |

**Recommendation:** **Whisper** (or Whisper.cpp) for best Polish accuracy. **Vosk** if you need low latency and low resource usage.

### Intent Recognition (NLU) - Polish Support

| Tool | Polish Support | Notes |
|---|---|---|
| **Rasa NLU** | Language-agnostic | Best option. Train your own Polish intents. Supports spaCy Polish pipeline (`pl_core_news_sm`). Open-source, self-hostable |
| **Snips NLU** | Language-agnostic | Lightweight. Supports custom languages including Polish. Good for IoT/embedded use cases |
| **Padatious (Mycroft)** | Language-agnostic | Simple intent parser using example sentences. Easy to add Polish |
| **Adapt (Mycroft)** | Language-agnostic | Keyword-based intent parser. Works with any language |

**Recommendation:** **Rasa NLU** for production quality. **Snips NLU** for lightweight/simple setups.

### Text-to-Speech (TTS) - Polish Support

| Tool | Polish Support | Quality | Notes |
|---|---|---|---|
| **Piper TTS** | Excellent | High | Best option. Multiple Polish voices available. Fast, lightweight. By Rhasspy project. Output: WAV/MP3 |
| **Coqui TTS** | Yes | High | Neural TTS. Polish models via community. `pip install TTS` |
| **eSpeak-ng** | Yes | Low | Robotic but functional. Built-in Polish. Very lightweight |
| **MaryTTS** | Limited | Medium | Java-based. Some Polish support via MBROLA voices |
| **MBROLA** | Yes | Medium | Diphone synthesis. Polish voices `pl1` available |

**Recommendation:** **Piper TTS** - best quality-to-resource ratio for Polish, and outputs MP3/WAV that Spencer can play directly.

---

## Recommended Server Stack for Polish Spencer

A minimal self-hosted server combining the best tools:

```
Your Server (Python/Flask or Node.js)
├── POST /tts/v1/text:synthesize
│   └── Piper TTS (Polish voice) → base64 MP3 response
│
└── POST /sti/speech
    ├── Whisper or Vosk (Polish ASR) → transcript
    └── Rasa NLU or Snips NLU (Polish intents) → intent + entities
```

### Example Python server skeleton (Flask):

```python
from flask import Flask, request, jsonify
import whisper
import piper
import base64

app = Flask(__name__)

@app.route('/tts/v1/text:synthesize', methods=['POST'])
def tts():
    data = request.get_json()
    text = data['input']['text']
    # Generate speech with Piper TTS (Polish)
    audio_mp3 = generate_polish_speech(text)
    return jsonify({'audioContent': base64.b64encode(audio_mp3).decode()})

@app.route('/sti/speech', methods=['POST'])
def sti():
    wav_data = request.data
    # Transcribe with Whisper (Polish)
    transcript = transcribe_polish(wav_data)
    # Detect intent with your NLU
    intent, entities = detect_intent(transcript)
    return jsonify({
        'text': transcript,
        'intents': [{'name': intent, 'confidence': 0.9}],
        'entities': entities
    })
```

---

## Summary Table

| Feature | Polish Support | Change Required | Difficulty |
|---|---|---|---|
| **TTS (Text-to-Speech)** | Likely possible | Client-side: change `languageCode` and `name` in `TextToSpeech.cpp` | Low |
| **Speech Recognition (STI)** | Not possible without server changes | Server-side: add Polish ASR + NLU model | High |
| **Language Persistence** | Not implemented | Add `language` field to `SettingsData` in `Settings.h` | Low |
