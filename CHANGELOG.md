# Changelog

## 1.0.1

- Fixed: the battery icon in the panel now matches the real charge instead of always showing three quarters.

## 1.0.0

- First release.
- Smart mode: fans follow your curve while plugged in and in use, otherwise macOS runs them.
- Minimum and maximum speed, ramp temperatures, away timeout, and Quiet, Balanced and Cool presets.
- Settings window with live readings for each fan and a graph of your fan curve.
- Menu bar fan that spins with the real fan speed, with optional temperature and speed.
- Privileged helper registered through SMAppService, talking over signature checked XPC. Sirocco registers it on launch and restarts it if it stops answering.
- Automatic updates through Sparkle.
