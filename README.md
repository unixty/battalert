# BattAlert

BattAlert is a lightweight battery monitoring script for Linux laptops.

It runs as a `systemd` service and sends desktop notifications (with sound) when battery charge reaches configured thresholds.

## Features

- Upper and lower battery threshold alerts
- Repeating critical notifications until charger state changes
- Sound playback for high/low alerts
- Language support: English and Russian notifications
- Interactive installer with threshold and language selection

## Default Settings

- Lower threshold: `40%`
- Upper threshold: `80%`
- Language: `en`

## Install

Run from the project directory:

```bash
sudo bash install.sh
```

The installer will ask for:

- Lower threshold percentage
- Upper threshold percentage
- Language (`en` or `ru`)

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
```

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
