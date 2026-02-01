# Unofficial Microsoft Edit (msedit) APT Repository

This repository provides automatically built `.deb` packages for [Microsoft Edit (msedit)](https://github.com/microsoft/edit) for Debian/Ubuntu based systems.

## Quick Install (Bootstrap Method)
You only need to install the package once. It will automatically add the repository and GPG key to your system for future updates.

1. Download the latest `.deb` for your architecture (amd64 or arm64) from the [pool directory](https://github.com/KingsleyLeung03/msedit-apt/tree/gh-pages/pool/main/m/msedit).
2. Install it:
   ```bash
   sudo apt install ./msedit_VERSION_ARCH.deb
   ```

*You will now receive updates via `sudo apt upgrade`.*

## Manual Install
If you prefer to configure it manually:

```bash
# Import Key
wget -qO- https://KingsleyLeung03.github.io/msedit-apt/public.key | sudo gpg --dearmor -o /usr/share/keyrings/msedit-archive-keyring.gpg

# Add Repo
echo "deb [signed-by=/usr/share/keyrings/msedit-archive-keyring.gpg] https://KingsleyLeung03.github.io/msedit-apt ./" | sudo tee /etc/apt/sources.list.d/msedit.list

# Install
sudo apt update
sudo apt install msedit
```

## Disclaimer
This is an unofficial repository and is not affiliated with Microsoft.
