![waydroi-fix banner](./images.jpeg)

# waydroi-fix

Helper script to repair, (optionally) reset, and customize a Waydroid installation on Linux.

This repository provides a Bash script, `waydroid.sh`, that can:

- Optionally **reset** Waydroid (delete data, reinstall package, re-download images)
- Apply **network fixes** (IP forwarding, NAT, dnsmasq) to help Waydroid get online
- Initialize Waydroid with either **GAPPS** or **VANILLA** images
- Start the Waydroid container
- Integrate with the excellent **[waydroid_script](https://github.com/casualsnek/waydroid_script)** project to customize Waydroid (GApps, Magisk, Widevine, microG, etc.)

> **Important:** This script is not affiliated with, endorsed by, or maintained by the authors of `waydroid_script`. It only uses their public project as a helper for post-install customization.

---

## Overview

`waydroi-fix` tries to solve two common problems:

1. **"My Waydroid is broken / won’t start / has no network"**
2. **"I want a quick way to apply GApps / Magisk / microG / Widevine and other tweaks"**

It does this in two main phases:

1. **Fix / Reset phase (optional)** – clean up and re-initialize Waydroid.
2. **Customization phase** – hand off to [`waydroid_script`](https://github.com/casualsnek/waydroid_script) to apply extra features.

You can choose to run only the customization phase (no reset) if your existing Waydroid installation is already fine.

---

## Features

### 1. Optional reset

On start, the script asks if you want to fully reset Waydroid.

- If you choose **yes**:
  - It asks for a second confirmation (double safety).
  - Then it:
    - Stops Waydroid services
    - Unmounts stuck mounts
    - Removes Waydroid data directories
    - Reinstalls the `waydroid` package (on supported systems)
    - Re-downloads images (GAPPS or VANILLA, your choice)
    - Re-enables and starts the container
  - This is useful when Waydroid is badly broken or you want a completely fresh start.

- If you choose **no**:
  - It **skips all destructive operations**.
  - Your existing Waydroid data and images are left untouched.
  - The script goes straight to the customization phase.

### 2. Network fixes

During the reset path, the script attempts to fix common networking issues:

- Enables IPv4 forwarding via `sysctl`.
- Writes a small sysctl config file so the setting persists.
- Detects your default network interface (via `ip route`).
- Adds an iptables MASQUERADE rule on the default interface (if `iptables` is available).
- Ensures `dnsmasq` is installed (on Fedora-based systems) to avoid DNS problems inside Waydroid.

These steps help Waydroid get a working network connection even on systems without firewalld.

### 3. Waydroid initialization

If you choose to reset, the script will re-initialize Waydroid and ask which image type you want:

- **GAPPS** – comes with Google Play services and Play Store.
- **VANILLA** – no Google apps, more minimal.

It uses explicit OTA URLs for system and vendor images to avoid common `waydroid init` OTA URL errors.

### 4. `waydroid_script` integration

Instead of re‑implementing all the advanced Android tweaks, this script:

- Uses an existing local checkout of `waydroid_script` if it finds one.
- If not, clones `https://github.com/casualsnek/waydroid_script` into:
  - `~/.local/share/waydroid_script`
- Creates or reuses a Python virtual environment (`venv`) in that directory.
- Installs Python dependencies from `requirements.txt`.
- Ensures the required `lzip` package is installed, using the appropriate package manager where possible (`dnf`/`apt`/`pacman`/`zypper`).
- Finally runs:

  ```bash
  sudo venv/bin/python3 main.py
  ```

From there, **all customization logic is provided by `waydroid_script`**. Typical things you can do inside `waydroid_script` include (see its README for details and exact options):

- Install OpenGApps (`install gapps`)
- Install Magisk (`install magisk`)
- Install `libndk` / `libhoudini` for ARM translation
- Install Widevine L3 DRM support
- Install microG, Aurora Store, Aurora Droid
- Apply hacks like `nodataperm` or `hidestatusbar`

> This project just automates getting to a clean, working Waydroid + launching `waydroid_script`. All Android‑side magic belongs to `waydroid_script`.

---

## Requirements

- A Linux distribution with Waydroid available (tested primarily on Fedora‑based systems).
- Root/sudo access (required for system configuration, networking, package installs).
- `bash`
- `git` (for cloning/updating `waydroid_script`).
- A supported package manager for automatic `lzip` installation, or install `lzip` manually:
  - `dnf`, `apt`, `pacman`, or `zypper`.

If your distribution uses a different package manager, you can still use this script, but you may need to install `lzip` and `waydroid` manually first.

---

## Usage

### 1. Make the script executable

```bash
chmod +x waydroid.sh
```

### 2. Run with sudo

```bash
sudo ./waydroid.sh
```

You should run it with sudo so it can:

- Stop/start system services
- Manage networking (iptables, sysctl)
- Install required packages like `lzip` and `dnsmasq`

### 3. Choose whether to reset

When the script starts, you will see a question similar to:

- **"Reset Waydroid? (y/n)"**

- If you answer **`y`**:
  - It will ask one more time for confirmation.
  - If you confirm, it runs the full reset, network fixes, and re‑initialization flow.

- If you answer **`n`**:
  - It prints a message that it is skipping reset.
  - Your current Waydroid install is left as‑is.

### 4. Select image type (reset path only)

If you chose to reset, you will be asked to pick:

- `1` – **GAPPS** (recommended if you need Google Play)
- `2` – **VANILLA** (no Google apps)

The script then downloads the selected images using `waydroid init` and starts the Waydroid container.

### 5. Customization with `waydroid_script`

After the reset step (or immediately, if you skipped it), the script will:

1. Prepare a directory for `waydroid_script` under `~/.local/share/waydroid_script`.
2. Reuse an existing checkout if it already exists (updating it with `git pull` when possible).
3. Create a Python `venv` and install `requirements.txt`.
4. Ensure `lzip` is installed using your distro’s package manager (or fail with a clear error if it cannot be installed automatically).
5. Run:

   ```bash
   sudo venv/bin/python3 main.py
   ```

At this point you are inside `waydroid_script`'s own interactive menu / command interface. Refer to its README for all available subcommands.

---

## Example scenarios

### Scenario A: Everything is broken, start fresh with GApps

1. Run:

   ```bash
   sudo ./waydroid.sh
   ```
2. Choose **reset = yes** and confirm.
3. Select **GAPPS** when asked for image type.
4. Wait for download and initialization to finish.
5. `waydroid_script` launches:
   - Use its options to install OpenGApps, Magisk, Widevine, microG, etc.

### Scenario B: Waydroid works, just want Magisk/microG

1. Run:

   ```bash
   sudo ./waydroid.sh
   ```
2. Answer **no** when asked to reset Waydroid.
3. The script skips all destructive steps and jumps straight into `waydroid_script`.
4. Use `waydroid_script` to install whatever tweaks you need on your existing Waydroid installation.

---

## Safety notes

- A full reset can **delete all Waydroid data** (apps, settings, user data). Read the prompts carefully.
- The script touches networking (IP forwarding, iptables) and may install packages using your distro’s package manager.
- Always review the script before running it, especially if you adapt it to a different distribution.

---

## Relationship to `waydroid_script`

This project *depends on* and *wraps around* the upstream **[`waydroid_script`](https://github.com/casualsnek/waydroid_script)** project:

- All advanced Android / Waydroid customization logic is implemented there.
- This repository just adds a convenience shell wrapper around:
  - Cleaning / reinstalling Waydroid
  - Applying some basic network fixes
  - Ensuring required host‑side tools like `lzip` are present
  - Creating a Python environment and launching `waydroid_script`

> **Credits:** Full credit for the customization functionality (GApps, Magisk, microG, Widevine, SmartDock, hacks, etc.) goes to the maintainer(s) of `waydroid_script`.

If you use this project, please also:

- **Star and support the original [`waydroid_script`](https://github.com/casualsnek/waydroid_script) repository.**
- Report issues about customization behavior to that project when appropriate (this repo only controls the wrapper script around it).
