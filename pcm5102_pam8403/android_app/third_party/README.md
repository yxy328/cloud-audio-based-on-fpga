# USB serial driver dependency

Source: https://github.com/mik3y/usb-serial-for-android/tree/v3.10.0

Pinned archive SHA256: D4567AA07CE3984D05B0C8689E44C0373254810A2338C951AC59364BE8DD6960

License: MIT, retained in usbserial-LICENSE.txt and upstream source headers; also bundled in the APK as assets/third_party/usbserial-LICENSE.txt.

The driver Java files and MonotonicClock/UsbUtils/HexDump utilities are copied into app/src/main/java/com/hoho/android/usbserial. A local BuildConfig supplies DEBUG=false. The source-only androidx IntDef annotation/import was removed from UsbSerialPort.java to keep this repository's direct javac/D8 build without an AndroidX dependency. No driver runtime logic was changed. The app enables 32 queued 4096-byte USB requests and uses read(timeout=0), following the upstream high-rate receive guidance; port close cancels the requests.

Recording requires an adapter which really supports 2Mbps and automatic RTS/CTS receive flow control, rather than assuming support from a nominal USB serial device name. This dependency adds no audio playback capability.
