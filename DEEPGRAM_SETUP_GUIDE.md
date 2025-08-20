# 🎧 **Nova + Deepgram STT Integration Setup Guide**

Nova now includes professional-grade **Deepgram STT** for real-time audio transcription! This guide will help you configure the system properly.

---

## 🚀 **What's New**

✅ **Professional Deepgram STT** - High-accuracy speech-to-text with Nova-2 model  
✅ **Real-time transcription** - Live transcript display in the overlay  
✅ **Smart filtering** - Removes repetitive content and filler words automatically  
✅ **Vector memory integration** - Important speech content stored in Nova's memory system  
✅ **Clean transcripts** - Only actual speech content, no system noise  
✅ **50ms chunking** - Optimal real-time performance  

---

## 🔑 **Step 1: Get Your Deepgram API Key**

1. **Go to** https://console.deepgram.com/
2. **Sign up** or log in to your account
3. **Navigate to** "API Keys" in the sidebar
4. **Click** "Create a New API Key"
5. **Name it** "Nova STT"
6. **Copy the key** (starts with random characters, not "dk_" or similar)

---

## ⚙️ **Step 2: Configure Nova**

### **Option A: Environment Variable (Recommended)**
```bash
# In Terminal, before running Xcode:
export DEEPGRAM_API_KEY="your_actual_deepgram_key_here"
open cheatingai.xcodeproj
```

### **Option B: Direct Configuration**
1. **Open** `cheatingai/System/DeepgramConfig.swift`
2. **Replace** line 18:
   ```swift
   return "YOUR_DEEPGRAM_API_KEY_HERE"
   ```
   **With your actual key:**
   ```swift
   return "your_actual_deepgram_key_here"
   ```

---

## 📱 **Step 3: Test the Integration**

### **Build and Run**
1. **Open** the Xcode project
2. **Build and run** (⌘+R)
3. **Grant permissions** when prompted:
   - Screen Recording permission (System Settings)

### **Test Transcription**
1. **Open** any audio source (YouTube, Spotify, etc.)
2. **Click** the "Listen" button in Nova's overlay
3. **Watch** the live transcript appear in real-time
4. **Click** "Stop" to save the clean transcript

---

## 🎯 **How It Works**

### **Audio Capture**
- **ScreenCaptureKit** captures system audio (no drivers needed)
- **16kHz mono 16-bit** format optimized for Deepgram
- **50ms chunks** sent to Deepgram for real-time processing

### **Transcription Pipeline**
```
System Audio → ScreenCaptureKit → AudioPipeline → Deepgram STT → Clean Transcript
```

### **Smart Filtering**
- **Removes duplicates** (85% similarity threshold)
- **Filters filler words** (um, uh, like, basically)
- **Skips repetitive content** (thank you for watching, etc.)
- **Quality filtering** (minimum length, confidence thresholds)

### **Memory Integration**
- **Important speech content** automatically stored in vector memory
- **Context analysis** determines memory type (personal, preference, etc.)
- **Importance scoring** based on content relevance

---

## 📋 **Transcript Output**

### **What You'll Get**
```
SESSION TRANSCRIPT
==================
Session ID: FC2E6842-D2C3-4F29-A678-83582F140377
Start Time: 2025-08-20 15:53:38
End Time: 2025-08-20 15:54:00
Total Transcript Segments: 3

SUMMARY
-------
Audio transcription completed

TRANSCRIPT
----------

[15:53:46] [S] Welcome to today's presentation about artificial intelligence
[15:53:52] [S] We'll be exploring the latest developments in machine learning
[15:54:00] [S] Let's start with the fundamentals of neural networks

END OF TRANSCRIPT
```

### **What's Filtered Out**
❌ System messages and metadata  
❌ Repetitive phrases  
❌ Filler words and artifacts  
❌ Empty or very short utterances  
❌ Duplicate content  

---

## 🔧 **Configuration Options**

### **DeepgramConfig.swift Settings**
```swift
// Model settings
"model": "nova-2"              // Latest high-accuracy model
"encoding": "linear16"         // 16-bit PCM
"sample_rate": "16000"         // 16kHz
"smart_format": "true"         // Auto punctuation
"interim_results": "true"      // Live results
"endpointing": "1000"          // 1 second silence = utterance end
```

### **Chunk Size**
- **Default**: 1600 bytes (50ms at 16kHz mono)
- **Adjustable** in `DeepgramConfig.chunkSizeBytes`

### **Keep-Alive**
- **Interval**: 5 seconds
- **Prevents** connection timeout during silence

---

## 🐛 **Troubleshooting**

### **No Transcription Appearing**
1. ✅ **Check API key** is configured correctly
2. ✅ **Verify internet connection** 
3. ✅ **Ensure audio is playing** (YouTube, etc.)
4. ✅ **Grant Screen Recording permission**

### **Poor Transcription Quality**
1. ✅ **Check audio source quality**
2. ✅ **Ensure proper audio levels** (not too quiet/loud)
3. ✅ **Try different audio source**

### **Connection Issues**
1. ✅ **Check API key validity** at Deepgram console
2. ✅ **Verify network connectivity**
3. ✅ **Check firewall settings**

### **Build Errors**
1. ✅ **Clean build folder** (Shift+⌘+K)
2. ✅ **Check Swift version** (Xcode 15+)
3. ✅ **Verify target SDK** (macOS 13.0+)

---

## 📊 **Performance & Quality**

### **Accuracy**
- **90-95%** accuracy for clear speech
- **Real-time processing** with minimal latency
- **Professional-grade** quality matching industry standards

### **Latency**
- **50ms chunks** for optimal real-time performance
- **Network latency** + **processing time** (typically <500ms)
- **Live transcript** updates in real-time

### **Bandwidth**
- **32KB/second** for 16kHz mono audio
- **Efficient streaming** with minimal data usage

---

## 🎉 **You're All Set!**

Nova now has professional-grade speech-to-text capabilities! The system will:

✅ **Capture system audio** automatically  
✅ **Transcribe in real-time** with Deepgram STT  
✅ **Filter and clean** transcripts automatically  
✅ **Store important content** in vector memory  
✅ **Save clean transcripts** to files  

**Start by clicking "Listen" and speaking or playing audio to see the magic happen!** 🎤✨

---

## 💡 **Pro Tips**

1. **Test with different audio sources** (YouTube, podcasts, meetings)
2. **Use good quality audio** for best results
3. **Check the live transcript** for real-time feedback
4. **Browse saved transcripts** in the Sessions tab
5. **Let Nova learn** from your transcripts for better memory context

**Enjoy your enhanced Nova experience with professional STT!** 🚀
