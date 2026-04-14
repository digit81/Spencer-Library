"""
Spencer Polish Voice Server
----------------------------
Drop-in replacement for spencer.circuitmess.com running on a Raspberry Pi.
Provides TTS (Piper) and Speech-to-Intent (Vosk + keyword NLU) endpoints.

Usage:
    uvicorn main:app --host 0.0.0.0 --port 8080
"""

import base64
import io
import json
import os
import re
import subprocess
import tempfile
import wave

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

import vosk

app = FastAPI()

# ---------------------------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------------------------
VOSK_MODEL_PATH = os.environ.get("VOSK_MODEL", "model")
PIPER_BIN = os.environ.get("PIPER_BIN", "piper")
PIPER_MODEL = os.environ.get("PIPER_MODEL", "pl_PL-darkman-medium.onnx")

# ---------------------------------------------------------------------------
# Vosk model (loaded once at startup)
# ---------------------------------------------------------------------------
vosk.SetLogLevel(-1)
model = vosk.Model(VOSK_MODEL_PATH)

# ---------------------------------------------------------------------------
# Polish intent definitions (keyword-based)
# ---------------------------------------------------------------------------
INTENTS = {
    "weather": [
        "pogoda", "pogodę", "temperatura", "temperaturę", "stopni",
        "pada", "deszcz", "słonecznie", "ciepło", "zimno", "prognoza",
        "wiatr", "śnieg",
    ],
    "time": [
        "godzina", "godzinę", "czas", "która", "zegarek", "minuty", "zegar",
    ],
    "joke": [
        "żart", "dowcip", "śmieszne", "opowiedz", "kawał", "zabawne",
        "rozśmiesz", "pośmiej",
    ],
    "greeting": [
        "cześć", "dzień dobry", "hej", "witaj", "siema", "halo",
    ],
    "name": [
        "nazywasz", "imię", "kim jesteś", "jak masz na imię", "twoje imię",
    ],
    "music": [
        "muzyka", "muzykę", "zagraj", "piosenka", "piosenkę", "śpiewaj",
    ],
    "thanks": [
        "dziękuję", "dzięki", "dziękować",
    ],
}


def match_intent(transcript: str):
    """Return (intent_name, confidence, entities) for the transcript."""
    text = transcript.lower()
    best_intent = None
    best_score = 0

    for intent_name, keywords in INTENTS.items():
        hits = sum(1 for kw in keywords if kw in text)
        if hits > best_score:
            best_score = hits
            best_intent = intent_name

    if best_intent is None:
        return None, 0.0, {}

    confidence = min(0.5 + best_score * 0.15, 0.99)
    return best_intent, confidence, {}


# ---------------------------------------------------------------------------
# TTS endpoint  –  POST /tts/v1/text:synthesize
# ---------------------------------------------------------------------------
@app.post("/tts/v1/text:synthesize")
async def tts_synthesize(request: Request):
    body = await request.body()
    body_str = body.decode("utf-8", errors="replace")

    # Spencer sends single-quoted pseudo-JSON with a fixed structure:
    #   { 'input': { 'text': 'CONTENT' }, 'voice': { ... }, 'audioConfig': { ... } }
    # A naive quote-swap breaks on apostrophes inside CONTENT. Instead,
    # anchor on the surrounding keys, which are constants controlled by
    # the firmware and can't appear in user text.
    match = re.search(
        r"'text'\s*:\s*'(.*)'\s*\}\s*,\s*'voice'",
        body_str,
        re.DOTALL,
    )
    if not match:
        return JSONResponse(
            {"error": "could not extract text from request"}, status_code=400
        )
    text = match.group(1)

    wav_path = None
    mp3_path = None
    try:
        # 1. Generate WAV with Piper
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            wav_path = f.name

        subprocess.run(
            [PIPER_BIN, "--model", PIPER_MODEL, "--output_file", wav_path],
            input=text, capture_output=True, text=True, check=True,
        )

        # 2. Convert WAV → MP3 (16 kHz mono, 32 kbps to fit Spencer's flash slot)
        # At 32 kbps: ~4 KB/sec, so 128 KB flash slot fits ~32 seconds of audio.
        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
            mp3_path = f.name

        subprocess.run([
            "ffmpeg", "-y", "-i", wav_path,
            "-ar", "16000", "-ac", "1",
            "-codec:a", "libmp3lame", "-b:a", "32k",
            "-loglevel", "error",
            mp3_path,
        ], capture_output=True, check=True)

        with open(mp3_path, "rb") as f:
            mp3_data = f.read()

        return JSONResponse({"audioContent": base64.b64encode(mp3_data).decode()})

    except subprocess.CalledProcessError as e:
        return JSONResponse({"error": str(e)}, status_code=500)

    finally:
        for path in (wav_path, mp3_path):
            if path and os.path.exists(path):
                os.unlink(path)


# ---------------------------------------------------------------------------
# STI endpoint  –  POST /sti/speech
# ---------------------------------------------------------------------------
@app.post("/sti/speech")
async def sti_speech(request: Request):
    wav_data = await request.body()

    wav_path = None
    try:
        # Write incoming WAV to disk for wave module
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(wav_data)
            wav_path = f.name

        # Transcribe with Vosk
        wf = wave.open(wav_path, "rb")
        rec = vosk.KaldiRecognizer(model, wf.getframerate())

        while True:
            data = wf.readframes(4000)
            if len(data) == 0:
                break
            rec.AcceptWaveform(data)

        result = json.loads(rec.FinalResult())
        transcript = result.get("text", "")
        wf.close()

        # Match intent
        intent, confidence, entities = match_intent(transcript)

        response = {"text": transcript}
        if intent:
            response["intents"] = [{"name": intent, "confidence": confidence}]
        else:
            response["intents"] = []
        if entities:
            response["entities"] = entities

        return JSONResponse(response)

    finally:
        if wav_path and os.path.exists(wav_path):
            os.unlink(wav_path)
