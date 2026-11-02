# When app audio is silent

1. Install version 0.9.0 on the creator and listeners. Turn on the creator’s hotspot, connect all listeners to it, then recreate the room and join with its six-digit code. Compare the separate security code on both phones and approve both before audio is shared.
2. Keep listener apps open, unmute their output, and raise their media volume. On the creator, tap **Test room speakers**. This stops any active sharing session and sends a short chime.
3. If the chime is audible on the listeners, the room can deliver sound. Select **App audio → Share device audio**, approve Android's sharing request, then open your audio/video app and press play. Keep the creator phone unlocked.
4. Return to Beatrazeem and read the app-audio status. If audio pauses when you switch away from the source app, check the same status on a listener while the source keeps playing.

| Status | Meaning / next step |
| --- | --- |
| Waiting for app sound | Sharing has started; allow a few seconds while audio plays. |
| Sound detected | The creator has captured non-silent audio. If listeners remain silent, check their volume/output route and whether the speaker test works. |
| No app sound detected | Android is supplying silent audio. The source may be paused, disallow capture, or be affected by a device limitation. Try another source app or non-protected content. This message alone cannot identify the reason. |
| Audio capture is not responding | No audio blocks arrived for several seconds. Stop sharing and start it again, approving the new request. |

If the test chime is also silent, this is not just an app-capture issue. Check the selected speaker in Android settings, listener volume and mute, and try the phones' built-in speakers. Report whether the listener says **Room audio data has reached this phone**.

For further troubleshooting, report the phone model and Android version shown in the creator's App audio card, the source app/content, the capture status while it plays, and whether the test chime is audible on listeners.

Android 10+ supports playback capture, including Android 16, but the source app and content must allow it and run in the same Android user profile. Permission to share the screen does not override a source app's audio-capture policy. See [Android's playback-capture documentation](https://developer.android.com/media/platform/av-capture). The device-wide consent request uses [Android's media-projection configuration](https://developer.android.com/media/grow/media-projection).

This is a development build. The software checks do not establish physical-device audio compatibility or synchronization.

## Checking synchronization

Update every phone to 0.9.0, recreate the room, leave speaker timing adjustments at 0 ms, and run Test room speakers first with built-in speakers. Compare the joined phones to each other. The creator’s original YouTube/Spotify playback is not delayed by capture and will be earlier. Keep app-audio monitoring off to avoid a delayed duplicate. If joined phones remain offset, report their models, whether the offset stays constant or grows, and whether it also happens with the test chime.

## Checking Karaoke

- If you hear your microphone but no music, set **Backing music** above 0% and **Singer level** to 100%. Try **App audio** mode and use the status checks above to confirm the source app supplies capturable sound. Microphone sound alone does not prove that music capture is working.
- If music plays but your voice is missing, check Android microphone access and the **Your microphone** level, stop other recording apps, and restart Karaoke. Keep the phone microphone unobstructed.
- If Singer level barely changes a song, it may not have centered stereo vocals. The control applies a vocal-band effect and can also affect instruments; it does not isolate the singer.
- If the creator hears two copies of the music, switch **Karaoke mix on this device** off and listen on joined phones. Beatrazeem cannot mute or process the original playback inside the source app.
- For feedback or whistling, lower microphone/output volume and move the microphone farther from speakers. A shared playback delay remains, and Bluetooth can increase it.
- Karaoke continues using the microphone while the source app is open. Return to Beatrazeem and tap **Stop sharing** to end it.

## Joining the creator's hotspot

1. Update **every phone** to 0.9.0. On the creator, enable the hotspot in Android settings before creating the room.
2. Connect all listeners to that hotspot through their Wi-Fi settings. The creator stays the hotspot provider; it does not join a listener's network.
3. Keep Beatrazeem's room open on the creator. Enter its six-digit code on each listener. The app checks the actual gateway address; no IP address entry or file upload is needed.
4. If Android says the hotspot has no internet, choose to remain connected. The room itself does not need internet. A source app may still need internet to play music.
5. If the phone changes Wi-Fi networks, leave the room and join again. VPNs or device hotspot restrictions may still interfere with local traffic.

## Persistent offsets and increasing delay

Start the speaker test with manual timing set to 0 ms on every phone. A constant offset between joined phones may need the existing **Your speaker → Adjust speaker timing** control if a device's audio route lacks reliable presentation timestamps. Bluetooth adds route-dependent latency. Compare joined outputs separately from the creator's unprocessed source app.

The new clock path, speaker-rate tracking, capture timestamps, and bounded listener queues address software causes of accumulated delay. A slow connection may now skip audio instead of replaying old queued sound. No acoustic synchronization measurements were possible in this build environment.

## Reading Live delay

Open **Your speaker → Live delay** on each phone while audio plays. The single millisecond value estimates elapsed time between capture and playback for samples rendered on that phone. It refreshes once per second when fresh speaker timestamps are available.

**Measuring…** means fresh timing is unavailable; it does not mean zero delay. **Output is off** appears when Beatrazeem is not playing on that phone. The estimate is not a microphone measurement of the actual sound. It cannot measure how far apart two phones sound, and Bluetooth can add delay that the driver does not report.

Timing adjustments run automatically. The Resync button has been removed. The existing **Adjust speaker timing** guide remains available for a consistent audible offset.

## Broken or choppy app audio

Version 0.9.0 fixes abrupt capture timestamp changes, small gaps at packet boundaries, loss of useful packets during capture bursts, and slow recovery after an output interruption. Install it on every phone and recreate the room. Start with built-in speakers and manual adjustments at 0 ms. Compare the room chime, then captured app audio on the joined phones for ten minutes. Keep creator app-audio monitoring off to avoid a delayed duplicate of its original source sound.

If the joined phones still stutter or separate, record their Live delay readings and whether the problem starts immediately or grows. Real-device tests are needed to distinguish Wi-Fi stalls, source capture behavior, and output-driver latency. The creator's original source-app playback remains outside Beatrazeem's shared buffer.
