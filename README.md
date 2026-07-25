(Disclaimer: I made this project to solve a specific problem I was facing. Which is, not finding a decent app to use my phone as a mic for my pc. Most apps that I found were either paid, complicated to use, or had ads every damn hour. So even tho I don't have much coding experience, I built this tool with massive help from claude code. So if you feel like the code quality is messy, please feel free to make a pull request)

# Meo Mic

Use your Android phone as a wireless microphone for your PC. Simple, lightweight, and free

<img width="400" height="750" alt="Screenshot 2025-12-17 145040" src="https://github.com/user-attachments/assets/29f88143-1b3b-415a-bfc8-e41f3878204b" />


## Features

- **Real-time audio streaming** over WiFi
- **Auto-discovery** - Phone finds PC automatically on the same network
- **Volume control** - Adjust input volume on both phone and PC (0-200%)
- **Mute button** - Quick mute/unmute from your phone
- **Low latency** - Optimized UDP streaming with latency display
- **Modern UI** - Beautiful Catpuccin-themed dark interface
- **Open source** - Free forever

## Download

### PC App (Windows)
Download `MeoMic-Windows.zip` from [Releases](../../releases)

### Android App
Download `MeoMic.apk` from [Releases](../../releases)

## Screenshots

| Android App | 
|-------------|
|<img src="https://github.com/user-attachments/assets/714a0e75-f48d-40b5-96be-c27ffd640eb1" width="400">
## Quick Start

### Step 1: Install the Apps

**PC:**
1. Extract `MeoMic-Windows.zip`
2. Run `MeoMic.exe` from the extracted folder
3. (Optional) Create a desktop shortcut to `MeoMic.exe`

**Android:**
1. Download and install `MeoMic.apk`
2. Allow installation from unknown sources if prompted
3. Grant microphone permission when asked

### Step 2: Install VB-Cable (Windows) — one click

Windows has no built-in way for an app to appear as a microphone, so Meo Mic needs
a virtual audio driver. On first run, the setup wizard offers to do this for you:

1. Click **Install VB-Cable**
2. Approve the Windows administrator prompt
3. Click **Install Driver** in VB-Audio's installer
4. Click **Restart now** when Meo Mic offers it

Meo Mic downloads the driver pack straight from `vb-audio.com`, verifies its
Authenticode signature before running anything, and launches VB-Audio's own
installer unmodified. Nothing is bundled or repackaged.

Prefer to do it yourself? The wizard's **Install manually instead** section has
the same steps, or grab it from [vb-audio.com/Cable](https://vb-audio.com/Cable/).

> VB-CABLE is donationware by VB-Audio (Vincent Burel). If you find it useful,
> consider [donating to them](https://vb-audio.com/Cable/) — they make it possible.

### Step 3: Connect

1. Make sure both devices are on the **same WiFi network**
2. Open Meo Mic on your PC - note the IP address shown
3. Open Meo Mic on your phone
4. Tap **"Search for PC"** or enter the IP address manually
5. You should see "Connected" on both apps

### Step 4: Configure Audio Output

In the PC app:
- Select **"CABLE Input (VB-Audio Virtual Cable)"** from the dropdown
- This sends audio TO the virtual cable

### Step 5: Use in Your Apps

In Discord, Zoom, Teams, OBS, etc.:
- Go to audio/microphone settings
- Select **"CABLE Output (VB-Audio Virtual Cable)"** as your microphone
- This receives audio FROM the virtual cable

## Controls

### Android App
| Control | Function |
|---------|----------|
| Mute Button (green/red) | Toggle microphone mute |
| Volume Slider | Adjust input volume (0-200%) |
| Disconnect Button | End the connection |

### PC App
| Control | Function |
|---------|----------|
| Device Dropdown | Select audio output device |
| Volume Slider | Adjust output volume (0-200%) |
| VB-Cable Setup | Open setup wizard |

## Building from Source

### PC App (Python)

```bash
cd pc-app
pip install -r requirements.txt
python main.py
```

To build executable:
```bash
build_windows.bat
```
The app will be in `dist\MeoMic\MeoMic.exe`

### Android App

1. Open `android-app` folder in Android Studio
2. Sync Gradle files
3. Build → Generate Signed Bundle / APK → APK
4. Create/select a keystore
5. Build release APK

## Technical Details

| Specification | Value |
|---------------|-------|
| Protocol | Custom UDP packets |
| Audio Format | 48kHz, 16-bit, Mono PCM |
| Port | 48888 |
| Discovery | mDNS/Zeroconf (`_meomic._udp.local.`) |

## Requirements

### PC
- Windows 10 or later
- VB-Cable virtual audio driver

### Android
- Android 7.0 (API 24) or higher
- Microphone permission
- Same WiFi network as PC

## Troubleshooting

### No audio in Discord/Zoom/etc.
1. Make sure you selected **"CABLE Input"** in the Meo Mic PC app
2. Make sure you selected **"CABLE Output"** as microphone in Discord/Zoom
3. Check that the audio level bar moves when you speak

### Phone shows "Connected" but PC doesn't
- Check Windows Firewall - allow Meo Mic through
- Try disabling VPN
- Restart both apps

### High latency
- Move closer to your WiFi router
- Use 5GHz WiFi instead of 2.4GHz
- Close bandwidth-heavy apps

### PC app takes long to start
- Make sure you're using the folder version (not single .exe)
- Extract the entire ZIP before running

### "CABLE Input" not showing
- Make sure VB-Cable is installed (VB-Cable Setup → **Install VB-Cable**)
- Restart your PC after installation — the device does not appear until you do
- Check Device Manager for VB-Audio device

### One-click install failed
- **"Signature could not be verified"** — Meo Mic refuses to run an installer it
  can't verify. Use the wizard's **Install manually instead** steps.
- **"Administrator permission was declined"** — VB-Cable installs a driver, so
  Windows requires elevation. Click **Try again** and approve the prompt.
- **Download failed** — check your connection or a corporate proxy/firewall, then
  fall back to the manual steps.

## License

MIT License - Free to use and modify

## Contributing

Contributions welcome! Feel free to open issues or pull requests.

---

Made with love using Python, Kotlin, and Jetpack Compose
