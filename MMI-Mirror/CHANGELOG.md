# MMI Mirror 开发变更记录

## 2026-09-06 — V2 / Stage 1.1 统一 Cluster HMI 控制面

- 最终 Java/HMI 架构收敛为**一个 `carplay_hook.jar` 控制面**，不再计划长期维护两个会覆盖 OEM HMI 类的独立 JAR；
- 固定最终组合契约：`ctx80={98,101,102,3}`：`98=RGI overlay`、`101/102=OEM KDK backing`、`3=replaceable BaseVideo`；
- `displayable3` 继续抽象为 BaseVideo plane：当前数据源为完整 MMI Capture，未来可无缝替换为真正 CarPlay second-screen video；
- 新增 `Cluster-HMI/` 构建层：以用户当前 `mib2q-carplay-rgi-cn` 为 RGI 业务逻辑基线，并叠加 Luka 最新 `DisplayManagerMIB2High` ownership seam；
- 新增 `ClusterStateController`：统一承担 Layout/View observer、最终 context lifecycle/ownership 以及未来 RGI presentation state seam；
- HMI observer 从 OEM `NAV_VIEW_SIZE_CHOICE` 与活动 Layout 生成 `/tmp/mmi-mirror-hmi.state`，供 Native BaseVideo 动态选择四套独立 geometry；
- V2 Native 新增 `/tmp/mmi-mirror-basevideo.ready`：只有首个有效帧成功 present 后才发布 ready；硬恢复和退出前撤销；
- Launcher 新增两种 context owner：`native70`（V2A 首轮实车）与 `java80`（最终组合迁移）；`java80` 下 Native 自动 `--no-route` 并关闭 native reconciliation，保证 Java 是唯一 context writer；
- `Cluster-HMI` 的 source-preparer 将 Luka 的 `ctx80={98,101,102,33}` 改造为项目目标 `{98,101,102,3}`，并将 ScreenModule 专属 ownership gate 改为共享 `ClusterStateController`；
- **本次不迁移现有 RGI `20/74`**；V2A 仍保持 legacy RGI 可回滚基线，后续 V2B 再单独完成 `20 -> 98` 与 `74 -> 80`；
- 仓库中已验证的 `Toolbox/apps/carplay-rgi/carplay_hook.jar` 与 `Toolbox/apps/mmi-mirror/mmi-mirror-display` 二进制暂不替换，必须先分别通过 Java/P1404 LSD 和 QNX ARMv7 build gate。

## 2026-09-05 — Stage 1 Base Video / 最终架构骨架

- 在修改前把干净显示底层 `main@3213bf2` 备份为 `backup-clean-display-backend`；
- 固定最终 display 分工：`3=Base Video`、`98=RGI`、`101/102=KDK backing`；
- 固定最终组合目标：`ctx80={98,101,102,3}`，不重新绑定原厂 active `20/33`；
- 新增 `VideoFrame`、`ClusterVideoSource`、`DisplayStateMachine` 和 RGI 占位接口；
- `MmiMirrorDisplay` 重构为通用 `ClusterVideoDisplay`，为未来 true second screen 保留同一输出接口；
- 新增 `MmiCaptureSource`：精确寻找 1024x480 MMI physical display，使用 QNX `screen_read_display()`；
- 支持 stride-aware frame upload；BGRA/BGRX 由 GLES shader 交换 R/B，避免逐帧 CPU 通道转换；
- 增加 GPU destination rectangle，Stage 1 默认 0.80 source scale、居中；
- 新增 `--mmi` 前台 Base Video 模式与 `scripts/start_mmi_mirror.sh`；
- 保留 first-frame-before-route；连续捕获失败先恢复 context72，再等待新首帧后重新 route；
- Stage 1 仍只使用已验证 `displayable3/context70/display4`，不启用 RGI/98/context80。

## 2026-09-04 — VNC-free 显示底层

- 移除 `rfb_client.cpp/.h`、VNC 启动脚本及全部 RFB/TCP/ZLIB 配置；
- 构建依赖移除 `-lsocket`、`-lz`；
- 新增 `MmiMirrorDisplay` 统一 RGBA → VC 显示接口；
- 保留 stock `libdisplayinit.so` + persistent handle + EGL/GLES2 + displayable 3/context 70；
- 保留 first-frame-before-route 与 context 72 恢复逻辑；
- binary 更名为 `mmi-mirror-display`；
- Test Grid 仅保留为故障隔离工具，不再作为开发前必做回归；
- 下一阶段只新增本地 `MmiCaptureSource`。
