# MHI2Q CarPlay Route Guidance Toolbox Integration

## 中文说明

### 项目简介

本项目将 **MHI2Q CarPlay Route Guidance Interface（CarPlay RGI）** 集成到 **MIB2 High Toolbox** 中，为原本需要通过命令行手动部署和修改配置文件的 CarPlay RGI，提供可直接在车机 Green Engineering Menu 中操作的安装、更新、卸载、日志收集和日志清理功能。

CarPlay RGI 的核心目标是让 MHI2Q 主机能够接收 CarPlay 导航应用发送的路线引导数据，并将转向、车道、距离、预计到达时间等信息呈现在 Virtual Cockpit 和 HUD 上。

### 基于的项目

本项目整合了以下两个开源项目：

1. [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi)

   提供 CarPlay RGI 的核心实现和四个运行组件：

   - `libcarplay_hook.so`
   - `maneuver_render`
   - `flag_atlas.rgba`
   - `carplay_hook.jar`

2. [jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox)

   提供 MIB2 High Toolbox、SD 卡部署结构、Green Engineering Menu 框架以及车机端脚本运行环境。

本项目的工作重点是将两者连接起来，为 CarPlay RGI 增加完整、可重复执行且带有备份和日志记录的 Toolbox 管理流程。CarPlay RGI 的核心功能和运行组件版权归其原作者所有；MIB2 High Toolbox 的原有内容遵循其上游许可证。

### CarPlay RGI 的主要作用

根据上游 CarPlay RGI 项目的当前实现，安装后可以提供：

- 将 Apple Maps、Google Maps、Waze 等 CarPlay 导航应用的路线引导信息发送至 Virtual Cockpit 和 HUD。
- 显示转向图标、车道引导、路口信息、出口编号、下一步操作距离和距离进度条。
- 显示当前道路、目的地、剩余距离、预计到达时间和剩余行程时间等文字信息。
- 通过 MOST 视频通道在仪表地图区域渲染自定义 3D 转向画面。
- 将 CarPlay 播放的专辑封面转发至仪表媒体界面。
- 将 MMI 触摸板滑动操作桥接为 CarPlay 方向键输入。

本项目**不会激活原本未开通的 CarPlay/App-Connect 功能**，也不会在仪表上实现完整的 CarPlay AltScreen 镜像。它是在已经能够正常使用 CarPlay 的兼容 MHI2Q 主机上增加路线引导及相关增强功能。

### 本项目所做的修改

#### 独立的 Green Engineering Menu 页面

新增菜单页面：

`Main > MQBCoding > Customization > CarPlay Route Guidance`

该页面包含四个操作按钮：

1. **Install/Update CarPlay Route Guidance Interface**
2. **Restore/Uninstall CarPlay Route Guidance Interface**
3. **Copy CarPlay RGI runtime logs to SD-card**
4. **Clear CarPlay RGI runtime logs**

菜单定义文件为：

`Toolbox/GEM/mqb-carplayRouteGuidance.esd`

#### 四个管理脚本

##### `install_carplay_rgi.sh`

负责首次安装和后续更新：

- 检查 SD 卡、四个源组件以及两个车机配置文件是否存在。
- 检查 `smartphone_integrator.json` 和 `dio_manager.json` 当前是否处于未安装或完整安装状态。
- 拒绝处理只有部分 RGI 标记、重复标记或注入位置不正确的异常配置，避免继续叠加修改。
- 首次安装时备份原始 `smartphone_integrator.json` 和 `dio_manager.json`，已有原始备份不会被后续安装覆盖。
- 将 `LD_PRELOAD` 准确加入 `carplay.envs`，并注入 `0x5200` 至 `0x5204` 路线引导消息定义。
- 将四个 RGI 组件复制到车机，并设置正确权限。
- 重复执行时进入更新模式，用 SD 卡中的四个新组件替换车机内的旧版本，同时保留最初的原车 JSON 备份。
- 安装过程中创建临时事务快照；发生脚本错误或捕获到中断信号时，尝试恢复到本次安装开始前的状态。
- 安装结束前检查四个组件及所有配置标记，并保存修改后的 JSON 副本。

##### `uninstall_carplay_rgi.sh`

负责恢复和卸载：

- 在修改车机之前确认两个原始 JSON 备份都存在。
- 使用最初备份恢复 `smartphone_integrator.json` 和 `dio_manager.json`。
- 删除车机中的四个 CarPlay RGI 组件。
- 检查两个配置文件已经恢复且四个组件已经移除。
- 脚本可以重复执行；如果一次卸载未完成，可以在条件恢复后再次执行。

##### `collect_carplay_rgi_logs.sh`

负责收集运行日志：

- 将 `/tmp/carplay_hook.log` 复制到 SD 卡。
- 将 `/tmp/maneuver_render.log` 复制到 SD 卡。
- 使用临时文件完成复制后再替换目标文件，降低产生不完整日志副本的概率。
- 如果当前运行日志不存在，则保留 SD 卡上已有的上一次收集副本。

##### `clear_carplay_rgi_logs.sh`

负责清空车机运行日志：

- 清空 `/tmp/carplay_hook.log`。
- 清空 `/tmp/maneuver_render.log`。
- 采用截断为 0 字节的方式，而不是删除文件，因此已经打开日志文件的进程仍可继续向同一文件写入新记录。

### 安装位置

四个 CarPlay RGI 组件会被部署到：

| 组件 | 车机目标位置 |
| --- | --- |
| `libcarplay_hook.so` | `/mnt/app/root/hooks/libcarplay_hook.so` |
| `maneuver_render` | `/mnt/app/root/hooks/maneuver_render` |
| `flag_atlas.rgba` | `/mnt/app/root/hooks/flag_atlas.rgba` |
| `carplay_hook.jar` | `/mnt/app/eso/hmi/lsd/jars/carplay_hook.jar` |

安装程序还会修改：

- `/mnt/system/etc/eso/production/smartphone_integrator.json`
- `/mnt/system/etc/eso/production/dio_manager.json`

### 备份与日志

所有备份及管理日志按车机固件版本存放在 SD 卡的以下目录：

`Backup/<VERSION>/CarPlayRGI/`

其中包括：

- `smartphone_integrator.json`：首次安装前的原始文件。
- `dio_manager.json`：首次安装前的原始文件。
- `smartphone_integrator_new.json`：最近一次成功安装后的文件副本。
- `dio_manager_new.json`：最近一次成功安装后的文件副本。
- `install_carplay_rgi.log`：安装和更新过程记录。
- `uninstall_carplay_rgi.log`：恢复和卸载过程记录。
- `carplay_hook.log`：收集到的 CarPlay hook 运行日志。
- `maneuver_render.log`：收集到的 3D 渲染器运行日志。

请妥善保管原始 JSON 备份，不要手动修改或删除备份目录中的文件。

### 基本使用方法

1. 将完整 Toolbox 文件放入 FAT32 格式的 SD 卡。
2. 按照 MIB2 High Toolbox 的正常方式将 Toolbox 和新增 GEM 页面部署到车机。
3. 保持 Toolbox SD 卡插入车机。
4. 进入 `MQBCoding > Customization > CarPlay Route Guidance`。
5. 选择安装/更新按钮，等待脚本明确提示安装成功。
6. 文件写入结束后至少等待 30 秒，再重启车机。
7. 需要排查问题时，先复现问题，再使用日志收集按钮将运行日志复制到 SD 卡。
8. 需要重新开始记录时，使用日志清理按钮，然后再次复现问题。

如需更新 CarPlay RGI，只需将新的四个组件放入 `Toolbox/apps/carplay-rgi/`，再次执行安装/更新按钮即可。

### 兼容性与风险提示

- 本功能面向 **Audi MHI2Q** 平台，不应直接用于 MIB1、MIB2 Standard、MHI2 或其他未经确认的平台。
- 上游 RGI 组件可能与具体固件版本有关；用于其他版本前应确认二进制兼容性。
- 安装前应确认 CarPlay 本身已经正常工作，并完整保存 SD 卡中的备份。
- 本项目会修改车机系统配置和持久化文件，操作可能导致功能异常、系统无法启动或保修失效。
- 所有操作均由使用者自行承担风险。作者及上游项目维护者不对设备损坏、数据丢失或其他后果负责。

---

## English Description

### Overview

This project integrates the **MHI2Q CarPlay Route Guidance Interface (CarPlay RGI)** into the **MIB2 High Toolbox**. It replaces the original command-line deployment procedure with a dedicated Green Engineering Menu page for installing, updating, restoring, uninstalling, collecting logs, and clearing logs directly on the head unit.

The core purpose of CarPlay RGI is to let an MHI2Q head unit receive route-guidance data from CarPlay navigation apps and present maneuvers, lanes, distances, ETA, and related information on the Virtual Cockpit and HUD.

### Upstream Projects

This integration is based on two open-source projects:

1. [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi)

   This project provides the CarPlay RGI implementation and its four runtime components:

   - `libcarplay_hook.so`
   - `maneuver_render`
   - `flag_atlas.rgba`
   - `carplay_hook.jar`

2. [jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox)

   This project provides the MIB2 High Toolbox, its SD-card deployment structure, the Green Engineering Menu framework, and the on-device script environment.

The main contribution of this project is the integration layer between them: a repeatable Toolbox workflow with automatic configuration changes, persistent original backups, validation, recovery, and diagnostic logging. The CarPlay RGI implementation and binaries remain the work of their original authors, and the original MIB2 High Toolbox content remains subject to its upstream license.

### CarPlay RGI Features

Based on the current upstream CarPlay RGI implementation, the installed components can provide:

- Route-guidance data from CarPlay navigation apps such as Apple Maps, Google Maps, and Waze on the Virtual Cockpit and HUD.
- Maneuver icons, lane guidance, junction details, exit numbers, distance to the next action, and a distance bargraph.
- Current-road, destination, remaining-distance, ETA, and remaining-time text information.
- Custom 3D maneuver rendering in the cluster map area through the MOST video path.
- CarPlay album-art forwarding to the cluster media display.
- MMI touchpad swipe-to-DPAD bridging for CarPlay input.

This project **does not activate CarPlay/App-Connect on a unit where it is not already enabled**, and it does not provide full CarPlay AltScreen mirroring on the cluster. It adds route guidance and related enhancements to a compatible MHI2Q unit with working CarPlay.

### Changes Included in This Integration

#### Dedicated Green Engineering Menu Page

A new page is added at:

`Main > MQBCoding > Customization > CarPlay Route Guidance`

It contains four actions:

1. **Install/Update CarPlay Route Guidance Interface**
2. **Restore/Uninstall CarPlay Route Guidance Interface**
3. **Copy CarPlay RGI runtime logs to SD-card**
4. **Clear CarPlay RGI runtime logs**

The menu definition is stored in:

`Toolbox/GEM/mqb-carplayRouteGuidance.esd`

#### Four Management Scripts

##### `install_carplay_rgi.sh`

Handles both first-time installation and later updates:

- Checks the SD card, all four source components, and both production configuration files.
- Detects whether the configuration is unmodified or already contains a complete RGI installation.
- Rejects partial, duplicated, malformed, or incorrectly placed RGI markers instead of applying further changes to an uncertain configuration.
- Saves the original `smartphone_integrator.json` and `dio_manager.json` during the first installation. Later runs never overwrite these original backups.
- Adds the `LD_PRELOAD` entry specifically to `carplay.envs` and registers route-guidance message IDs `0x5200` through `0x5204`.
- Copies all four RGI components to the head unit with the required permissions.
- In update mode, replaces the installed components with the four versions currently stored on the SD card while preserving the original JSON backups.
- Creates a temporary pre-install transaction snapshot and attempts to restore it if the script fails or receives a handled interruption signal.
- Verifies every component and configuration marker before completing, then stores copies of the resulting modified JSON files.

##### `uninstall_carplay_rgi.sh`

Restores the original configuration and removes RGI:

- Confirms that both original JSON backups exist before changing production files.
- Restores `smartphone_integrator.json` and `dio_manager.json` from the first-install backups.
- Removes all four CarPlay RGI components from the head unit.
- Verifies that both configuration files exist and that all four RGI components have been removed.
- Can be run again if a previous uninstall did not complete and the required conditions have been restored.

##### `collect_carplay_rgi_logs.sh`

Collects the two runtime logs:

- Copies `/tmp/carplay_hook.log` to the SD card.
- Copies `/tmp/maneuver_render.log` to the SD card.
- Stages each copy in a temporary file before replacing the destination, reducing the chance of leaving an incomplete collected copy.
- Retains an older collected copy on the SD card if the current runtime source log is missing.

##### `clear_carplay_rgi_logs.sh`

Clears the two runtime logs on the head unit:

- Clears `/tmp/carplay_hook.log`.
- Clears `/tmp/maneuver_render.log`.
- Truncates the files to zero bytes instead of unlinking them, allowing processes with existing open file handles to continue writing new messages to the same files.

### Installed Files

The four CarPlay RGI components are deployed to:

| Component | Destination on the head unit |
| --- | --- |
| `libcarplay_hook.so` | `/mnt/app/root/hooks/libcarplay_hook.so` |
| `maneuver_render` | `/mnt/app/root/hooks/maneuver_render` |
| `flag_atlas.rgba` | `/mnt/app/root/hooks/flag_atlas.rgba` |
| `carplay_hook.jar` | `/mnt/app/eso/hmi/lsd/jars/carplay_hook.jar` |

The installer also modifies:

- `/mnt/system/etc/eso/production/smartphone_integrator.json`
- `/mnt/system/etc/eso/production/dio_manager.json`

### Backups and Logs

All backups and management logs are grouped by the detected firmware version under:

`Backup/<VERSION>/CarPlayRGI/`

The directory can contain:

- `smartphone_integrator.json`: original file saved before the first installation.
- `dio_manager.json`: original file saved before the first installation.
- `smartphone_integrator_new.json`: copy of the file produced by the latest successful installation.
- `dio_manager_new.json`: copy of the file produced by the latest successful installation.
- `install_carplay_rgi.log`: installation and update history.
- `uninstall_carplay_rgi.log`: restore and uninstall history.
- `carplay_hook.log`: collected CarPlay hook runtime log.
- `maneuver_render.log`: collected 3D renderer runtime log.

Keep the original JSON backups safe. Do not manually edit or delete files in the backup directory.

### Basic Usage

1. Place the complete Toolbox structure on a FAT32-formatted SD card.
2. Deploy the Toolbox and the new GEM page using the normal MIB2 High Toolbox procedure.
3. Leave the Toolbox SD card inserted in the head unit.
4. Open `MQBCoding > Customization > CarPlay Route Guidance`.
5. Select the install/update action and wait for an explicit success message.
6. After the file operations finish, wait at least 30 seconds before rebooting the head unit.
7. To diagnose a problem, reproduce it first and then copy the runtime logs to the SD card.
8. To begin a clean logging session, clear the runtime logs and reproduce the issue again.

To update CarPlay RGI, replace the four files in `Toolbox/apps/carplay-rgi/` with the new versions and run the install/update action again.

### Compatibility and Risk Notice

- This integration targets the **Audi MHI2Q** platform. It should not be used directly on MIB1, MIB2 Standard, MHI2, or any other unverified platform.
- Upstream RGI binaries may be firmware-specific. Confirm binary compatibility before using them on a different firmware release.
- CarPlay should already be enabled and working before installation, and the SD-card backups should be preserved in a safe location.
- This project modifies system configuration and persistent files on the infotainment unit. Incorrect or incompatible use may cause malfunction, an unbootable unit, or loss of warranty.
- Use entirely at your own risk. Neither this project's author nor the upstream maintainers are responsible for device damage, data loss, or any other consequences.
