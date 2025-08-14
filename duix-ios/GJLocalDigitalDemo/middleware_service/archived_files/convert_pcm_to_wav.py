#!/usr/bin/env python3
import wave
import sys

def pcm_to_wav(pcm_file, wav_file, sample_rate=16000, channels=1, sample_width=2):
    """
    Convert raw PCM data to WAV format
    
    Args:
        pcm_file: Input PCM file path
        wav_file: Output WAV file path
        sample_rate: Sample rate (default 16000 Hz)
        channels: Number of channels (default 1 for mono)
        sample_width: Sample width in bytes (default 2 for 16-bit)
    """
    try:
        # Read PCM data
        with open(pcm_file, 'rb') as f:
            pcm_data = f.read()
        
        # Create WAV file
        with wave.open(wav_file, 'wb') as wav:
            wav.setnchannels(channels)
            wav.setsampwidth(sample_width)
            wav.setframerate(sample_rate)
            wav.writeframes(pcm_data)
        
        print(f"Successfully converted {pcm_file} to {wav_file}")
        print(f"Duration: {len(pcm_data) / (sample_rate * channels * sample_width):.2f} seconds")
        
    except Exception as e:
        print(f"Error converting PCM to WAV: {e}")
        return False
    
    return True

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python convert_pcm_to_wav.py <input_pcm_file> <output_wav_file>")
        sys.exit(1)
    
    pcm_file = sys.argv[1]
    wav_file = sys.argv[2]
    
    pcm_to_wav(pcm_file, wav_file) 