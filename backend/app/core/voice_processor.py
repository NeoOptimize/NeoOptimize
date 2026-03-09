# app/services/voice_processor.py
import whisper
import gtts
import base64
import tempfile
import shutil
import logging
from pathlib import Path

logger = logging.getLogger("VoiceProcessor")

class VoiceProcessor:
    def __init__(self):
        # PERBAIKAN: Load model langsung tanpa suffix "-tiny" di import
        self.model = whisper.load_model("tiny")  # Pilihan: tiny | base | small | medium | large
        logger.info("✅ Whisper model loaded successfully")

    def transcribe_audio(self, audio_path: str) -> str:
        """Transkripsi audio ke text"""
        result = self.model.transcribe(audio_path)
        return result["text"]

    def text_to_speech(self, text: str, lang: str = "id") -> bytes:
        """Text to Speech using gTTS"""
        tts = gtts.gTTS(text, lang=lang)
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".mp3")
        tts.save(temp_file.name)
        
        with open(temp_file.name, "rb") as f:
            audio_bytes = f.read()
        
        Path(temp_file.name).unlink()
        return audio_bytes