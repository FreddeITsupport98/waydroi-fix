![waydroi-fix banner](./images.jpeg)

# waydroi-fix

Helper script to repair, (optionally) reset, and customize a Waydroid installation on Linux.

This repository provides a Bash script, `waydroid.sh`, plus a small CLI helper, `way-fix`, that can:

- Ensure **Waydroid is installed** and offer to install it automatically on supported distros
- Optionally **reset** Waydroid (delete data, reinstall package, re-download images)
- Apply **network fixes** (IP forwarding, NAT, dnsmasq) to help Waydroid get online
- Initialize Waydroid with a **VANILLA** image or a **GAPPS** image (chosen via yes/no prompt)
- Start the Waydroid container
- Offer to install a global `way-fix` CLI (`way-fix`, `way-fix reboot`, `way-fix config`, `way-fix uninstall`)
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

### 1. Waydroid presence check

Before doing anything else, the script checks whether the `waydroid` command is available:

- If **Waydroid is missing**:
  - It asks if you want to install Waydroid now.
  - On supported distros (Fedora/RHEL, Debian/Ubuntu, Arch-based, openSUSE/SLES) it tries to install the `waydroid` package using the matching package manager.
  - If installation fails or the distro is unknown, it prints a clear error and exits so you can install Waydroid manually.
- If you decline installation, the script aborts because Waydroid is required for all further steps.

### 2. Optional reset

On start (after verifying Waydroid is installed), the script asks if you want to fully reset Waydroid.

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

### 3. Network fixes

During the reset path, the script attempts to fix common networking issues:

- Enables IPv4 forwarding via `sysctl`.
- Writes a small sysctl config file so the setting persists.
- Detects your default network interface (via `ip route`).
- Adds an iptables MASQUERADE rule on the default interface (if `iptables` is available).
- Ensures `dnsmasq` is installed (on Fedora-based systems) to avoid DNS problems inside Waydroid.

These steps help Waydroid get a working network connection even on systems without firewalld.

### 4. Waydroid initialization

If you choose to reset, the script will re-initialize Waydroid and ask if you want a GAPPS base image:

- Answer **y** → **GAPPS** – comes with Google Play services and Play Store.
- Answer **n** → **VANILLA** – no Google apps, more minimal.

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

### 5. Choose GAPPS base image (reset path only)

If you chose to reset, you will be asked if you want to use a GAPPS base image:

- Answer **y** → **GAPPS** (recommended if you need Google Play)
- Answer **n** → **VANILLA** (no Google apps)

The script then downloads the selected images using `waydroid init` and starts the Waydroid container.

### 6. Optional `way-fix` CLI install

After the reset decision (whether you reset or not), `waydroid.sh` will offer to install a global CLI helper:

- Installs `way-fix` into `/usr/local/bin/way-fix` (using `sudo install`) if you answer **y** and the `way-fix` script is present next to `waydroid.sh`.
- If you answer **n`, it skips CLI installation and continues.

Once installed, the `way-fix` command provides:

- `way-fix` – run the full fix/reset + customization flow (internally calls `waydroid.sh`)
- `way-fix reboot` – restart the Waydroid container service (`systemctl restart waydroid-container`)
- `way-fix config` – open the `waydroid_script` configuration menu (if already set up by `waydroid.sh`)
- `way-fix uninstall` – remove the `way-fix` CLI script itself

### 7. Customization with `waydroid_script`

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

## CLI usage (`way-fix`)

If you accepted the CLI install prompt or manually installed/symlinked `way-fix` into your `$PATH`, you can use:

```bash
way-fix              # open interactive WASD-style menu for common actions
way-fix reboot       # restart Waydroid container (shortcut)
way-fix config       # directly open waydroid_script configuration menu
way-fix uninstall    # remove the way-fix CLI script itself
```

### Interactive menu (default `way-fix`)

Running `way-fix` with no arguments shows a small, keyboard-driven menu:

```text
way-fix menu (use WASD, Enter = default, E = exit):
  [W] Open waydroid_script configuration menu
  [S] Restart Waydroid container
  [D] Uninstall way-fix CLI
  [E] Exit
```

Controls:

- **W / Enter** – Set up `waydroid_script` under `~/.local/share/waydroid_script` if needed (clone repo, ensure `lzip`, create venv, install `requirements.txt`), then launch its interactive `main.py` menu.
- **S** – Restart the Waydroid container with `sudo systemctl restart waydroid-container`.
- **D** – Ask for explicit confirmation before uninstalling the `way-fix` CLI:
  - Prints a warning with the path it will remove (e.g. `/usr/local/bin/way-fix`).
  - Prompts: `Type YES in capital letters to uninstall, anything else to cancel:`
  - Only an exact `YES` will remove the CLI; any other input cancels.
- **E** – Exit the `way-fix` menu.

Arrow keys are treated as a single invalid keypress (the escape sequence is consumed), and an error message is shown if an unsupported key is pressed.

### Direct commands

- **`way-fix reboot`**
  - Calls `sudo systemctl restart waydroid-container` directly.

- **`way-fix config`**
  - Runs the same logic as `[W]` from the menu: ensures `waydroid_script` and its venv are present, then launches `sudo venv/bin/python3 main.py`.

- **`way-fix uninstall`**
  - Non-interactive shortcut for removing the `way-fix` script from the path it is running from (for example `/usr/local/bin/way-fix`).
  - If it cannot remove the file with normal permissions, it will attempt to remove it using `sudo`.

### Assumptions and layout

- The deployed `way-fix` wrapper works independently at runtime; `waydroid.sh` is only used to install/update it into `/usr/local/bin/way-fix`.
- By default, `way-fix` will:
  - Create or reuse `~/.local/share/waydroid_script`.
  - Create or reuse the `venv` inside that directory.
  - Install Python dependencies from `requirements.txt` when needed.

If `waydroid_script` or its venv are missing, the wrapper will set them up automatically before launching the configuration menu.

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
