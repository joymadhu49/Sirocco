# Sirocco

[![CI](https://github.com/joymadhu49/Sirocco/actions/workflows/ci.yml/badge.svg)](https://github.com/joymadhu49/Sirocco/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/joymadhu49/Sirocco?label=download)](https://github.com/joymadhu49/Sirocco/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="Resources/AppIcon.png" width="160" alt="Sirocco icon" />
</p>

Fan control for Apple silicon MacBooks that only steps in when it helps: while you're plugged in and actually using the Mac. The rest of the time macOS runs the fans exactly as it always does.

A MacBook keeps its fans near minimum until the chip is hot, so under steady work the aluminium body soaks up the heat and gets uncomfortable to touch. Sirocco spins the fans up earlier, on a curve you set, so the case stays cool.

<p align="center">
  <img src="docs/panel.png" width="330" alt="The Sirocco panel" />
</p>

## Features

- **Smart mode.** Fans follow a curve from your Minimum to your Maximum as the chip warms up, but only while you're on power and at the Mac. Unplug or walk away and macOS takes over again.
- **Your limits.** Minimum and Maximum speed, the temperature where the ramp starts and where it hits full speed, and how long without input counts as away.
- **Presets.** Quiet, Balanced and Cool, scaled to your Mac's own fan range.
- **Max and Off.** Pin the fans at your Maximum, or hand them back to macOS entirely.
- **A fan that spins.** The menu bar icon turns at a speed that follows the real fans. It is animated by Core Animation, so it costs next to nothing, and it can be switched off.
- **Readouts.** Chip temperature, fan speed and power at a glance, in °C or °F, with an optional reading next to the icon.
- **Automatic updates**, signed and verified before they install.

## Install

Requires a Mac with Apple silicon and fans (MacBook Pro, Mac mini, Mac Studio and so on) running macOS 13 or later.

1. Download the latest `.dmg` from [Releases](https://github.com/joymadhu49/Sirocco/releases/latest).
2. Drag **Sirocco** into Applications and open it. The fan appears in the menu bar.
3. Click it, then **Turn On**. macOS opens System Settings: under General, Login Items & Extensions, switch on **Sirocco** in Allow in the Background.

The app is signed and notarized by Apple.

## How it works

Changing fan speeds needs root, and a menu bar app should not run as root. So Sirocco is two parts:

- **Sirocco.app**, the menu bar app you see. It runs as you.
- **SiroccoHelper**, a small daemon inside the app bundle, registered with launchd through `SMAppService`. It reads the temperature every two seconds and decides whether to drive the fans or leave them to macOS.

They talk over XPC, and both ends check the other's code signature: the helper only accepts the genuine Sirocco app signed by this developer team, and the app only trusts the genuine helper. Updating the app updates the helper too; it notices its binary was replaced and restarts itself.

### Safety

- Settings are clamped to the range your fans report, whatever is sent.
- Above 95°C the fans go to full speed regardless of your settings.
- When the helper stops (you remove it, delete the app, or shut down) it hands the fans back to macOS first.
- After sleep, when macOS reclaims the fans, the helper takes them back only if a boost is still wanted.

## Privacy

Sirocco collects nothing. The only network request is the daily update check, with system profiling turned off.

## Uninstall

Open the panel, click the **⋯** menu, choose **Remove Helper**, then drag Sirocco to the Trash. Removing the helper returns the fans to macOS immediately.

## Troubleshooting

The app has a command line mode for checking the helper:

```sh
/Applications/Sirocco.app/Contents/MacOS/Sirocco --helper status
/Applications/Sirocco.app/Contents/MacOS/Sirocco --helper register     # or unregister
```

The helper logs to `/Library/Logs/Sirocco.log`.

## Build from source

```sh
brew install xcodegen create-dmg
bash Scripts/build.sh --install
```

Fan control only works in a build signed with a Developer ID, because of the code signing checks above. A fork signed by another team sets its team ID in `Sources/Shared/Identity.swift` and its bundle identifiers in `project.yml`. Without a certificate the script signs ad hoc: the app runs and shows readings, but the helper refuses it.

`Scripts/release.sh` builds, notarizes, packages and signs a release locally, and prints the command to publish it.

## License

[MIT](LICENSE)
