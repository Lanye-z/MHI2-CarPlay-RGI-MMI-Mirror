# MIB2 Toolbox — CarPlay RGI + MMI Mirror

[English](README_EN.md) | 简体中文

本项目面向 Audi **MHI2Q / MIB2 High** 平台，将 **CarPlay Route Guidance（RGI）** 与 **MMI Mirror** 组合使用。CarPlay RGI 负责将 CarPlay 导航引导与相关交互扩展至 **Virtual Cockpit / HUD**，MMI Mirror 则将 MMI 中控画面实时镜像至 Virtual Cockpit 的地图显示区域，并通过 Green Engineering Menu 完成安装、启动、诊断与恢复。

> **重要：RGI 与 MMI Mirror 是两个独立安装步骤。** 如果需要同时使用 **CarPlay RGI + MMI Mirror**，必须**先安装 CarPlay RGI，再安装 MMI Mirror**。`Install/Update MMI Mirror` 不会代替 CarPlay RGI 的安装；如果未预先安装 RGI，则该流程只安装 MMI Mirror。


<img width="1920" height="1080" alt="bec01c5da5752c99fe7f3ac76b6bb919" src="https://github.com/user-attachments/assets/ec0417cc-0651-45c6-905d-9b12ce3a2ffc" />


<img width="1920" height="1080" alt="ebcac200dc8a2d82bfc4161e03833d49" src="https://github.com/user-attachments/assets/834a1d7f-2642-43cf-95b6-23eb6f6c184f" />



https://github.com/user-attachments/assets/6c3c6d34-4d87-4251-b04e-93c984747264



## 主要功能

- **CarPlay Route Guidance（RGI）**
  - 将 CarPlay 导航的转向、下一操作距离、距离进度、ETA、目的地等路线信息扩展至 Virtual Cockpit / HUD，并支持导航提供的 HUD 车道引导信息。
  - 通过 MOST 视频显示链路在仪表地图区域绘制 CarPlay 导航转向提示；无路线引导时保持原有地图显示。
  - 支持将 CarPlay 专辑封面转发到 Virtual Cockpit 的媒体界面。
  - 支持 **MMI 触控板 → DPAD** 输入桥接，可通过触控板滑动操作 CarPlay 菜单。
  - 保留方向盘滚轮的原车地图缩放交互，并可通过确认键切换仪表路线信息显示。
- **MMI Mirror**：将 MMI 中控画面实时镜像到 Virtual Cockpit 的地图显示区域。
- **RGI + MMI Mirror 组合使用**：在已经正确安装 CarPlay RGI 的基础上安装 MMI Mirror，使 RGI 与 MMI 镜像在同一套仪表显示环境中协同工作。
- **Toolbox 集成**：通过 Green Engineering Menu 完成 RGI 与 MMI Mirror 的安装、更新、日志收集和恢复，并提供 MMI Mirror 的启动、停止与 AutoStart，无需 SSH 执行日常操作。
- **AutoStart**：支持 MMI 完整开机后自动启动 MMI Mirror，也可切换回手动启动模式。
- **恢复与诊断**：提供 RGI / MMI Mirror 日志收集、临时日志清理以及恢复 / 卸载流程。

## 安装与使用

如果希望使用 **CarPlay RGI + MMI Mirror**，请严格按照以下顺序安装：

```text
安装 CarPlay RGI
        ↓
等待至少 30 秒后重启车机 / HMI
        ↓
确认 RGI 导航显示与交互正常
        ↓
安装 / 更新 MMI Mirror
        ↓
重启车机 / HMI
        ↓
手动启动 MMI Mirror 并确认正常
        ↓
按需开启 AutoStart
```

**不要先安装 MMI Mirror 再安装 RGI。** 组合方案以已经安装并正常工作的 CarPlay RGI 为前置基础。

如果只需要 MMI Mirror，不需要 CarPlay RGI，可以跳过 RGI 安装步骤，直接安装 MMI Mirror。

### 1. 更新 Toolbox

将本仓库中的 Toolbox 内容放入 MIB2 High Toolbox 使用的 SD 卡，并按照 Toolbox 的正常更新方式，将新增菜单、脚本和运行文件更新到车机。

Toolbox 更新完成后，**先退出 Green Engineering Menu，再重新进入**，使 CarPlay RGI 与 MMI Mirror 页面重新加载。

### 2. 安装 CarPlay RGI

如果需要使用 **RGI + MMI Mirror**，必须先完成本步骤。

重新进入 Green Engineering Menu 后，进入：

```text
Main > MQBCoding > Customization > CarPlay Route Guidance
```

`CarPlay Route Guidance` 页面提供以下操作：

| 菜单项 | 作用 |
| --- | --- |
| `Install/Update CarPlay Route Guidance Interface` | 首次安装或更新 CarPlay RGI。 |
| `Restore/Uninstall CarPlay Route Guidance Interface` | 卸载 RGI，并恢复安装前保存的相关文件与配置。 |
| `RESCUE - Force Restore Stock CarPlay / Remove RGI` | 正常恢复流程无法完成时，用于强制恢复原车 CarPlay / 移除 RGI。 |
| `Copy CarPlay RGI runtime logs to SD-card` | 将 CarPlay RGI 运行日志复制到 SD 卡。 |
| `Clear CarPlay RGI runtime logs` | 清空当前 RGI 运行日志，后续日志仍会继续写入同一文件。 |

首次安装时，保持 Toolbox SD 卡插入车机，然后选择：

```text
Install/Update CarPlay Route Guidance Interface
```

本仓库已经将 CarPlay RGI 的部署过程封装到 Toolbox 脚本中。安装程序会检查所需文件、备份车机原始文件与配置，并部署 RGI 所需的 CarPlay hook、仪表转向提示渲染组件、HMI 组件以及相关运行配置。正常使用时无需再通过 SSH 手动逐个复制文件。

安装过程中不要拔出 SD 卡，也不要中断车机供电。等待菜单明确显示安装成功，并出现类似以下提示：

```text
CarPlay Route Guidance Interface installed successfully
Please wait at least 30 seconds, then reboot the headunit.
```

**安装成功后不要立即强制重启。请至少等待 30 秒，让文件写入和同步完成，再重启车机 / HMI。**

重启完成后连接 iPhone 和 CarPlay，并实际启动一条导航路线进行确认。建议检查 Virtual Cockpit / HUD 路线引导、仪表地图区域转向提示、MMI 触控板操作以及原车地图和方向盘交互是否正常。

只有确认 **CarPlay RGI 已经能够独立正常工作** 后，再继续安装 MMI Mirror。

RGI 安装日志保存在：

```text
Backup/<VERSION>/CarPlayRGI/install_carplay_rgi.log
```

其中 `<VERSION>` 为当前车机固件版本。如果安装过程出现错误或回滚失败提示，请先根据该日志恢复 RGI 状态，不要继续安装 MMI Mirror。

### 3. 安装 MMI Mirror

如果需要 **RGI + MMI Mirror**，请先确认 CarPlay RGI 已经完成安装、重启，并可以独立正常工作。

随后进入：

```text
Main > MQBCoding > Customization > MMI Mirror
```

`MMI Mirror` 页面提供以下操作：

| 菜单项 | 作用 |
| --- | --- |
| `Install/Update MMI Mirror` | 首次安装或更新 MMI Mirror；不会单独安装 CarPlay RGI。 |
| `Start MMI Mirror` | 手动启动已经安装好的 MMI Mirror。 |
| `Stop MMI Mirror` | 停止当前正在运行的 MMI Mirror 会话。 |
| `AutoStart ON - start after MMI boot` | 开启 MMI Mirror 开机自动启动。 |
| `AutoStart OFF - manual start only` | 关闭后续开机自启动；不会停止当前已经运行的会话。 |
| `Copy MMI Mirror diagnostics to SD-card` | 将 MMI Mirror 诊断信息复制到 SD 卡。 |
| `Clear temporary MMI Mirror logs` | 清理临时 MMI Mirror 日志，不改变当前运行状态。 |
| `Restore/Uninstall MMI Mirror` | 卸载 MMI Mirror；如检测到 RGI，则恢复组合安装前的稳定 RGI JAR 与 renderer。 |

保持 Toolbox SD 卡插入车机，选择：

```text
Install/Update MMI Mirror
```

该步骤会安装 / 更新 MMI Mirror runtime 和统一 HMI 组件。如果检测到完整的 CarPlay RGI，安装程序还会将 RGI 的仪表转向提示 renderer 切换到 **RGI + MMI Mirror 组合显示**所需的版本；如果未检测到完整 RGI，则不会部署该组合 RGI renderer。

**安装完成后必须重启车机 / HMI。** 从 MMI Mirror 安装完成到重启之前，不要启动 MMI Mirror，也不要继续使用或判断 RGI 的显示状态，因为磁盘上的 HMI JAR / renderer 已经完成组合切换，而当前运行中的进程仍可能是重启前的状态。

完成一次完整重启后，再次进入：

```text
Main > MQBCoding > Customization > MMI Mirror
```

然后选择：

```text
Start MMI Mirror
```

先使用手动 `Start MMI Mirror` 确认 MMI 镜像与 RGI（如已安装）均正常，再决定是否开启 AutoStart。

MMI Mirror 安装日志保存在：

```text
Backup/<VERSION>/MMIMirror/install_mmi_mirror.log
```

### 4. 开启 AutoStart

确认 MMI Mirror 可以正常手动启动后，保持 Toolbox SD 卡插入，并选择：

```text
AutoStart ON - start after MMI boot
```

AutoStart 会建立持久化启动配置。后续完整 MMI 开机过程中，系统会等待车机运行环境和 MMI Mirror controller 就绪，再自动调用与手动 `Start MMI Mirror` 相同的启动路径。

配置成功后，**日常开机自动启动 MMI Mirror 不需要持续插入 SD 卡**。

如需恢复为手动启动模式，选择：

```text
AutoStart OFF - manual start only
```

`AutoStart OFF` 只关闭后续开机自启动；如果 MMI Mirror 当前已经运行，需要另外执行 `Stop MMI Mirror` 才会停止当前会话。

**更新 / 卸载 MMI Mirror，或重新安装 RGI 之前，建议先关闭 AutoStart。** 完成更新、重启并手动确认功能正常后，再重新开启。

### 5. 更新

#### 仅更新 MMI Mirror

如果已经开启 AutoStart，先执行：

```text
AutoStart OFF - manual start only
```

然后执行：

```text
Install/Update MMI Mirror
```

安装完成后重启车机 / HMI，再手动执行 `Start MMI Mirror` 确认功能正常。需要自动启动时，再重新开启 AutoStart。

#### 仅使用 RGI，更新 CarPlay RGI

如果车机只安装了 RGI，没有安装 MMI Mirror，可以直接执行：

```text
Install/Update CarPlay Route Guidance Interface
```

安装成功后等待至少 30 秒，再重启车机 / HMI，并确认 RGI 正常。

#### 已安装 RGI + MMI Mirror，需要更新 RGI

**不能只更新 RGI 后就继续按原组合状态使用。** MMI Mirror 的组合安装会使用统一 HMI JAR，并在完整 RGI 环境下切换对应 renderer；重新执行 RGI 安装后，需要再次安装 MMI Mirror 才能恢复组合状态。

正确顺序为：

```text
关闭 MMI Mirror AutoStart（如已开启）
        ↓
Install/Update CarPlay Route Guidance Interface
        ↓
等待至少 30 秒后重启车机 / HMI
        ↓
确认 RGI 独立工作正常
        ↓
Install/Update MMI Mirror
        ↓
再次重启车机 / HMI
        ↓
手动 Start MMI Mirror 并确认组合功能
        ↓
按需重新开启 AutoStart
```

### 6. 日志与故障排查

#### CarPlay RGI

RGI 出现导航信息不显示、仪表转向提示异常或 CarPlay 交互异常时，进入：

```text
Main > MQBCoding > Customization > CarPlay Route Guidance
```

选择：

```text
Copy CarPlay RGI runtime logs to SD-card
```

RGI 运行日志会保存到：

```text
Backup/<VERSION>/CarPlayRGI/
```

其中主要包括：

```text
carplay_hook.log
maneuver_render.log
```

需要从空日志重新复现问题时，可以先执行：

```text
Clear CarPlay RGI runtime logs
```

该操作清空当前 `/tmp` 中的 RGI 运行日志，后续运行信息会继续写入这些日志文件；不会删除此前已经复制到 SD 卡的日志。

#### MMI Mirror

MMI Mirror 无法启动、启动后退出，或 Virtual Cockpit 镜像显示异常时，进入：

```text
Main > MQBCoding > Customization > MMI Mirror
```

选择：

```text
Copy MMI Mirror diagnostics to SD-card
```

每次诊断会创建独立的时间戳目录，保存到：

```text
Backup/<VERSION>/MMIMirror/RuntimeLogs/<TIMESTAMP>/
```

诊断包不仅包含 MMI Mirror 自身日志，还会尽可能收集当前 CarPlay / RGI 相关日志、运行状态、进程信息和显示管理器快照，便于分析组合显示问题。

需要清理临时 MMI Mirror 日志后重新复现时，可以执行：

```text
Clear temporary MMI Mirror logs
```

该操作只清理可丢弃的临时日志和自检残留，**不会停止 MMI Mirror，也不会清除当前生命周期 / 显示状态标记**。需要停止镜像时请使用 `Stop MMI Mirror`。

### 7. 恢复 / 卸载

#### 只移除 MMI Mirror，保留 CarPlay RGI

如果开启过 AutoStart，先执行：

```text
AutoStart OFF - manual start only
```

然后选择：

```text
Restore/Uninstall MMI Mirror
```

如果检测到 RGI，卸载程序会恢复稳定的 RGI `carplay_hook.jar` 与 `maneuver_render`，并保留 RGI 的其他组件与配置。**卸载完成后必须重启车机 / HMI，再继续使用 RGI。**

#### 同时移除 MMI Mirror 与 CarPlay RGI

组合状态下应按照安装顺序的反向顺序恢复，**不要在 MMI Mirror 仍安装时直接卸载 RGI**。

正确顺序为：

```text
AutoStart OFF（如已开启）
        ↓
Restore/Uninstall MMI Mirror
        ↓
重启车机 / HMI
        ↓
确认 RGI 已恢复为独立状态
        ↓
Restore/Uninstall CarPlay Route Guidance Interface
        ↓
等待至少 30 秒
        ↓
再次重启车机 / HMI
```

如果只安装了 RGI，没有安装 MMI Mirror，则可直接执行 `Restore/Uninstall CarPlay Route Guidance Interface`；成功后等待至少 30 秒，再重启车机 / HMI。

只有在正常 RGI 恢复流程无法完成时，才考虑：

```text
RESCUE - Force Restore Stock CarPlay / Remove RGI
```

> 本项目会修改车机系统文件。请妥善保留 Toolbox 自动生成的备份，仅用于已经确认兼容的 Audi MHI2Q / MIB2 High 环境，所有操作风险由使用者自行承担。

## Acknowledgements

感谢以下项目和作者提供的基础工作与参考：

- [yuedizhibo / mib2q-MMI-Cockpit-Mirror](https://github.com/yuedizhibo/mib2q-MMI-Cockpit-Mirror) — 本项目 MMI Mirror 部分的主要基础，提供 MIB2Q 中控完整 MMI 画面实时镜像至 Virtual Cockpit 的实现基础。
- [luka-dev / mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi) — 本项目 CarPlay RGI、仪表路线引导及 MMI 触控板输入桥接等功能的核心上游基础。
- [OneB1t / VcMOSTRenderMqb](https://github.com/OneB1t/VcMOSTRenderMqb) — MQB Virtual Cockpit / MOST 自定义渲染研究的重要基础。
- [fifthBro / mh2p-cluster](https://github.com/fifthBro/mh2p-cluster) — QNX HMI 捕获及 GPU crop / zoom / pan 等实现思路的重要参考。
- [jilleb / mib2-toolbox](https://github.com/jilleb/mib2-toolbox) — MIB2 High Toolbox、Green Engineering Menu 与部署框架。

各上游文件与组件继续受其原始许可证和版权声明约束。
