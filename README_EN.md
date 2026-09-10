# MIB2 Toolbox — CarPlay RGI + MMI Mirror

[简体中文](README.md) | English

This project targets the Audi **MHI2Q / MIB2 High** platform and combines **CarPlay Route Guidance (RGI)** with **MMI Mirror**. CarPlay RGI extends CarPlay navigation guidance and related interactions to the **Virtual Cockpit / HUD**, while MMI Mirror mirrors the current MMI head-unit display in real time to the map area of the Virtual Cockpit. Installation, startup, diagnostics, and recovery are managed through the Green Engineering Menu.

> **Important: RGI and MMI Mirror are installed separately.** To use **CarPlay RGI + MMI Mirror** together, you must **install CarPlay RGI first, then install MMI Mirror**. `Install/Update MMI Mirror` does not install CarPlay RGI. If RGI has not already been installed, that procedure installs MMI Mirror only.

<img width="1920" height="1080" alt="bec01c5da5752c99fe7f3ac76b6bb919" src="https://github.com/user-attachments/assets/ec0417cc-0651-45c6-905d-9b12ce3a2ffc" />

<img width="1920" height="1080" alt="ebcac200dc8a2d82bfc4161e03833d49" src="https://github.com/user-attachments/assets/834a1d7f-2642-43cf-95b6-23eb6f6c184f" />

https://github.com/user-attachments/assets/6c3c6d34-4d87-4251-b04e-93c984747264

## Main Features

- **CarPlay Route Guidance (RGI)**
  - Extends CarPlay route information such as maneuvers, distance to the next action, distance progress, ETA, and destination information to the Virtual Cockpit / HUD, including lane guidance when provided by the navigation app.
  - Draws CarPlay maneuver guidance in the cluster map area through the MOST video display path; the original map remains available when no active route guidance is present.
  - Supports forwarding CarPlay album artwork to the Virtual Cockpit media display.
  - Supports **MMI touchpad → DPAD** input bridging, allowing CarPlay menus to be controlled using touchpad swipe gestures.
  - Preserves the OEM steering-wheel scroll-wheel interaction for map zoom and supports switching route-information views with the confirmation button.
- **MMI Mirror**: Mirrors the complete MMI center display in real time to the map area of the Virtual Cockpit.
- **RGI + MMI Mirror combination**: Installs MMI Mirror on top of a correctly installed CarPlay RGI environment so that RGI and MMI mirroring can work together within the same cluster display environment.
- **Toolbox integration**: Uses the Green Engineering Menu to install, update, collect logs, and restore both RGI and MMI Mirror, while also providing Start, Stop, and AutoStart controls for MMI Mirror. No SSH is required for normal day-to-day operation.
- **AutoStart**: Allows MMI Mirror to start automatically after a complete MMI boot, while still allowing the system to be switched back to manual startup mode.
- **Recovery and diagnostics**: Provides RGI / MMI Mirror log collection, temporary-log cleanup, and restore / uninstall workflows.

## Installation and Usage

To use **CarPlay RGI + MMI Mirror**, follow this installation order exactly:

```text
Install CarPlay RGI
        ↓
Wait at least 30 seconds, then reboot the head unit / HMI
        ↓
Confirm that RGI guidance and interaction work correctly
        ↓
Install / Update MMI Mirror
        ↓
Reboot the head unit / HMI
        ↓
Start MMI Mirror manually and verify normal operation
        ↓
Enable AutoStart if desired
```

**Do not install MMI Mirror before RGI.** The combined configuration assumes that CarPlay RGI has already been installed and verified to work correctly.

If you only need MMI Mirror and do not need CarPlay RGI, you may skip the RGI installation step and install MMI Mirror directly.

### 1. Update Toolbox

Copy the Toolbox contents from this repository to the SD card used by MIB2 High Toolbox, then use the normal Toolbox update procedure to deploy the new menus, scripts, and runtime files to the head unit.

After the Toolbox update is complete, **exit the Green Engineering Menu and enter it again** so that the CarPlay RGI and MMI Mirror pages are reloaded.

### 2. Install CarPlay RGI

If you want to use **RGI + MMI Mirror**, this step must be completed first.

After reopening the Green Engineering Menu, navigate to:

```text
Main > MQBCoding > Customization > CarPlay Route Guidance
```

The `CarPlay Route Guidance` page provides the following actions:

| Menu Item | Function |
| --- | --- |
| `Install/Update CarPlay Route Guidance Interface` | Installs CarPlay RGI for the first time or updates an existing installation. |
| `Restore/Uninstall CarPlay Route Guidance Interface` | Removes RGI and restores the files and configuration saved before installation. |
| `RESCUE - Force Restore Stock CarPlay / Remove RGI` | Forces restoration of stock CarPlay / removal of RGI if the normal recovery procedure cannot complete successfully. |
| `Copy CarPlay RGI runtime logs to SD-card` | Copies CarPlay RGI runtime logs to the SD card. |
| `Clear CarPlay RGI runtime logs` | Clears the current RGI runtime logs while allowing subsequent messages to continue being written to the same log files. |

For the first installation, keep the Toolbox SD card inserted and select:

```text
Install/Update CarPlay Route Guidance Interface
```

This repository packages the CarPlay RGI deployment procedure into Toolbox scripts. The installer checks the required files, backs up the original head-unit files and configuration, and deploys the CarPlay hook, cluster maneuver renderer, HMI component, and related runtime configuration required by RGI. Under normal use, there is no need to manually copy these files over SSH.

Do not remove the SD card or interrupt power while installation is in progress. Wait until the menu explicitly reports a successful installation and displays a message similar to:

```text
CarPlay Route Guidance Interface installed successfully
Please wait at least 30 seconds, then reboot the headunit.
```

**Do not force an immediate reboot after installation succeeds. Wait at least 30 seconds for file writes and synchronization to complete, then reboot the head unit / HMI.**

After rebooting, connect the iPhone and CarPlay and start an actual navigation route for verification. Check the Virtual Cockpit / HUD route guidance, maneuver display in the cluster map area, MMI touchpad interaction, and the OEM map / steering-wheel controls.

Only after **CarPlay RGI has been confirmed to work correctly on its own** should you continue with the MMI Mirror installation.

The RGI installation log is stored at:

```text
Backup/<VERSION>/CarPlayRGI/install_carplay_rgi.log
```

`<VERSION>` is the current head-unit firmware version. If the installer reports an error or rollback failure, restore the RGI state based on this log before attempting to install MMI Mirror.

### 3. Install MMI Mirror

If you want to use **RGI + MMI Mirror**, first confirm that CarPlay RGI has been installed, the head unit has been rebooted, and RGI works correctly by itself.

Then navigate to:

```text
Main > MQBCoding > Customization > MMI Mirror
```

The `MMI Mirror` page provides the following actions:

| Menu Item | Function |
| --- | --- |
| `Install/Update MMI Mirror` | Installs or updates MMI Mirror; it does not install CarPlay RGI by itself. |
| `Start MMI Mirror` | Manually starts the installed MMI Mirror. |
| `Stop MMI Mirror` | Stops the currently running MMI Mirror session. |
| `AutoStart ON - start after MMI boot` | Enables automatic MMI Mirror startup after a complete MMI boot. |
| `AutoStart OFF - manual start only` | Disables future automatic startup; it does not stop a session that is already running. |
| `Copy MMI Mirror diagnostics to SD-card` | Copies MMI Mirror diagnostic information to the SD card. |
| `Clear temporary MMI Mirror logs` | Clears temporary MMI Mirror logs without changing the current runtime state. |
| `Restore/Uninstall MMI Mirror` | Removes MMI Mirror; if RGI is detected, restores the stable RGI JAR and renderer used before the combined installation. |

Keep the Toolbox SD card inserted and select:

```text
Install/Update MMI Mirror
```

This step installs / updates the MMI Mirror runtime and unified HMI components. If a complete CarPlay RGI installation is detected, the installer also switches the RGI cluster maneuver renderer to the version required for the **combined RGI + MMI Mirror display**. If a complete RGI installation is not detected, the combined RGI renderer is not deployed.

**The head unit / HMI must be rebooted after installation completes.** Between completion of the MMI Mirror installation and the reboot, do not start MMI Mirror and do not continue using or evaluating the RGI display state. The HMI JAR / renderer on disk has already been switched to the combined configuration, while the currently running processes may still be using the pre-reboot state.

After a complete reboot, return to:

```text
Main > MQBCoding > Customization > MMI Mirror
```

Then select:

```text
Start MMI Mirror
```

Use `Start MMI Mirror` manually first to confirm that MMI mirroring and RGI (if installed) both operate normally before enabling AutoStart.

The MMI Mirror installation log is stored at:

```text
Backup/<VERSION>/MMIMirror/install_mmi_mirror.log
```

### 4. Enable AutoStart

After confirming that MMI Mirror starts correctly in manual mode, keep the Toolbox SD card inserted and select:

```text
AutoStart ON - start after MMI boot
```

AutoStart creates a persistent startup configuration. During subsequent complete MMI boots, the system waits for the head-unit runtime environment and the MMI Mirror controller to become ready, then invokes the same startup path used by `Start MMI Mirror`.

Once AutoStart has been configured successfully, **the SD card does not need to remain inserted for normal automatic MMI Mirror startup**.

To return to manual startup mode, select:

```text
AutoStart OFF - manual start only
```

`AutoStart OFF` only disables automatic startup on future boots. If MMI Mirror is currently running, use `Stop MMI Mirror` separately to stop the active session.

**It is recommended to disable AutoStart before updating / uninstalling MMI Mirror or reinstalling RGI.** After the update and reboot, verify the system manually before enabling AutoStart again.

### 5. Updating

#### Update MMI Mirror Only

If AutoStart is enabled, first select:

```text
AutoStart OFF - manual start only
```

Then run:

```text
Install/Update MMI Mirror
```

After installation completes, reboot the head unit / HMI and manually run `Start MMI Mirror` to verify normal operation. Re-enable AutoStart afterward if desired.

#### Update CarPlay RGI When Only RGI Is Installed

If only RGI is installed and MMI Mirror is not installed, run:

```text
Install/Update CarPlay Route Guidance Interface
```

After installation succeeds, wait at least 30 seconds, reboot the head unit / HMI, and verify that RGI works correctly.

#### Update CarPlay RGI When RGI + MMI Mirror Are Both Installed

**Do not update RGI and then continue using the previous combined configuration without reinstalling MMI Mirror.** The combined MMI Mirror installation uses a unified HMI JAR and switches to the corresponding renderer when a complete RGI environment is present. After reinstalling or updating RGI, MMI Mirror must be installed again to restore the combined configuration.

Use the following sequence:

```text
Disable MMI Mirror AutoStart (if enabled)
        ↓
Install/Update CarPlay Route Guidance Interface
        ↓
Wait at least 30 seconds, then reboot the head unit / HMI
        ↓
Confirm that RGI works correctly by itself
        ↓
Install/Update MMI Mirror
        ↓
Reboot the head unit / HMI again
        ↓
Start MMI Mirror manually and verify the combined configuration
        ↓
Re-enable AutoStart if desired
```

### 6. Logs and Troubleshooting

#### CarPlay RGI

If route information is missing, cluster maneuver rendering is abnormal, or CarPlay interaction behaves incorrectly, navigate to:

```text
Main > MQBCoding > Customization > CarPlay Route Guidance
```

Select:

```text
Copy CarPlay RGI runtime logs to SD-card
```

RGI runtime logs are saved to:

```text
Backup/<VERSION>/CarPlayRGI/
```

The main files include:

```text
carplay_hook.log
maneuver_render.log
```

To reproduce an issue from empty runtime logs, first run:

```text
Clear CarPlay RGI runtime logs
```

This clears the current RGI runtime logs under `/tmp`. New runtime messages will continue to be written to the same log files. Logs previously copied to the SD card are not deleted.

#### MMI Mirror

If MMI Mirror does not start, exits after startup, or the Virtual Cockpit mirror display is abnormal, navigate to:

```text
Main > MQBCoding > Customization > MMI Mirror
```

Select:

```text
Copy MMI Mirror diagnostics to SD-card
```

Each diagnostic collection creates a separate timestamped directory at:

```text
Backup/<VERSION>/MMIMirror/RuntimeLogs/<TIMESTAMP>/
```

The diagnostic package includes MMI Mirror logs and also attempts to collect relevant CarPlay / RGI logs, runtime state, process information, and display-manager snapshots to help analyze combined-display issues.

To clear temporary MMI Mirror logs before reproducing an issue, run:

```text
Clear temporary MMI Mirror logs
```

This only removes disposable temporary logs and self-check residue. It **does not stop MMI Mirror and does not clear the current lifecycle / display-state markers**. Use `Stop MMI Mirror` if you need to stop the mirror session.

### 7. Restore / Uninstall

#### Remove MMI Mirror but Keep CarPlay RGI

If AutoStart has been enabled, first select:

```text
AutoStart OFF - manual start only
```

Then select:

```text
Restore/Uninstall MMI Mirror
```

If RGI is detected, the uninstaller restores the stable RGI `carplay_hook.jar` and `maneuver_render` while keeping the remaining RGI components and configuration. **After uninstallation completes, reboot the head unit / HMI before continuing to use RGI.**

#### Remove Both MMI Mirror and CarPlay RGI

When both are installed, restore them in the reverse order of installation. **Do not uninstall RGI while MMI Mirror is still installed.**

Use the following sequence:

```text
AutoStart OFF (if enabled)
        ↓
Restore/Uninstall MMI Mirror
        ↓
Reboot the head unit / HMI
        ↓
Confirm that RGI has returned to standalone operation
        ↓
Restore/Uninstall CarPlay Route Guidance Interface
        ↓
Wait at least 30 seconds
        ↓
Reboot the head unit / HMI again
```

If only RGI is installed and MMI Mirror is not present, you may run `Restore/Uninstall CarPlay Route Guidance Interface` directly. After it succeeds, wait at least 30 seconds and then reboot the head unit / HMI.

Only if the normal RGI restore process cannot complete should you consider using:

```text
RESCUE - Force Restore Stock CarPlay / Remove RGI
```

> This project modifies system files on the head unit. Keep the backups generated by Toolbox in a safe place and use the project only on Audi MHI2Q / MIB2 High environments that have been confirmed compatible. All use is at your own risk.

## Acknowledgements

Special thanks to the following projects and authors for their foundational work and references:

- [yuedizhibo / mib2q-MMI-Cockpit-Mirror](https://github.com/yuedizhibo/mib2q-MMI-Cockpit-Mirror) — The primary foundation for the MMI Mirror portion of this project, providing the basis for real-time mirroring of the complete MIB2Q MMI display to the Virtual Cockpit.
- [luka-dev / mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi) — The core upstream foundation for CarPlay RGI, cluster route guidance, and MMI touchpad input bridging used by this project.
- [OneB1t / VcMOSTRenderMqb](https://github.com/OneB1t/VcMOSTRenderMqb) — An important foundation for MQB Virtual Cockpit / MOST custom-rendering research.
- [fifthBro / mh2p-cluster](https://github.com/fifthBro/mh2p-cluster) — An important reference for QNX HMI capture and GPU crop / zoom / pan implementation concepts.
- [jilleb / mib2-toolbox](https://github.com/jilleb/mib2-toolbox) — Provides the MIB2 High Toolbox, Green Engineering Menu, and deployment framework.

Upstream files and components remain subject to their respective original licenses and copyright notices.
