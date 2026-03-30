# BattAlert

BattAlert is a lightweight battery monitoring script for Linux laptops.

It runs as a `systemd` service and sends desktop notifications (with sound) when battery charge reaches configured thresholds.

## Features

- Upper and lower battery threshold alerts
- Repeating critical notifications until charger state changes
- Sound playback for high/low alerts
- Language support: English and Russian notifications
- Adjustable alert target volume (`VOLUME`, default `80`)
- Optional sleep inhibition while charging (`INHIBIT_SLEEP_ON_AC`)
- Optional temporary system volume boost during alert playback (`BOOST_SYSTEM_VOLUME_ON_ALERT`)
- Interactive installer with threshold, language, and sound/sleep settings

## Default Settings

- Lower threshold: `40%`
- Upper threshold: `80%`
- Language: `en`
- Alert target volume: `80`
- Inhibit sleep on AC: `1`
- Temporary system volume boost on alert: `0`

## Dependencies

Required commands:

- `systemd` (`systemctl`, `systemd-inhibit`)
- `notify-send`
- `gdbus`
- `sudo`
- `pw-cat` (typically from `pipewire-audio-client-libraries`, `pipewire-bin`, or `pipewire`)

Optional but recommended:

- `acpi`
- `wpctl` when `BOOST_SYSTEM_VOLUME_ON_ALERT=1`

## Install

Run from the project directory:

```bash
sudo bash install.sh
```

The installer will ask for:

- Lower threshold percentage
- Upper threshold percentage
- Language (`en` or `ru`)
- Sleep inhibition while charging (`1` or `0`)
- Temporary system volume boost for alert playback (`1` or `0`)
- Alert target volume (`0-100`) when temporary system volume boost is enabled

Then it will:

- Install `battalert.sh` to `/usr/local/bin/battalert.sh`
- Install `battalert.service` to `/etc/systemd/system/battalert.service`
- Create `/etc/default/battalert` with your settings
- Enable and start the `battalert.service`

## Uninstall

Run from the project directory:

```bash
sudo bash uninstall.sh
```

The uninstaller will:

- Stop and disable `battalert.service`
- Remove `/usr/local/bin/battalert.sh`
- Remove `/etc/systemd/system/battalert.service`
- Reload `systemd` daemon
- Ask whether to remove `/etc/default/battalert`

## Configuration

Configuration file:

`/etc/default/battalert`

Example:

```bash
LOWER=40
UPPER=80
LANG_CODE="en"
VOLUME=70
INHIBIT_SLEEP_ON_AC=1
BOOST_SYSTEM_VOLUME_ON_ALERT=0
```

If `BOOST_SYSTEM_VOLUME_ON_ALERT=1`, `VOLUME` is used as the temporary system output volume target for the alert, but only when the current sink is muted or below that level.

If `BOOST_SYSTEM_VOLUME_ON_ALERT=0`, the script plays the alert with `pw-cat --volume=1` and does not modify system volume.

After editing config manually, restart service:

```bash
sudo systemctl restart battalert.service
```

## Logs

Runtime log file:

`/tmp/battalert.log`

## Service Commands

```bash
sudo systemctl status battalert.service
sudo systemctl restart battalert.service
sudo systemctl stop battalert.service
sudo systemctl disable battalert.service
```
