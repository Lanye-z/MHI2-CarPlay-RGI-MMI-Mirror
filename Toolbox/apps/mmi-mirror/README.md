# MMI Mirror V2.2 / JAVA80 - Toolbox payload

本目录是 V2.2 final-cleanup 的 SD 卡安装源。最终架构固定为：Java `ClusterStateController` 是 terminal1 / ctx80 的唯一 context writer；Native MMI 与 Native RGI 只负责像素输出。当前 payload 状态为 **ARTIFACT VERIFIED / VEHICLE PENDING**。

## 1. Final ownership contract

```text
Java ClusterStateController = terminal1 / ctx80 sole writer
ctx80                       = {98,101,102,3}
Native RGI                  = displayable98 pixels only
Native MMI                  = displayable3 pixels only
```

`wantComposite`：

```text
(BaseVideo active && BaseVideo ready) || RGI frame active
```

Native MMI 源码与最终 ARM artifact 中均已删除旧 V2A `dmdt gs/sc/dc`、route/reconcile/restore framework，不再依赖 `--no-route` 或 `--no-context-reconcile` 开关保证安全。首帧仍保留原有双 submit 时序，只移除了两次 submit 中间已经 no-op 的 Native route 调用。

`/tmp/mmi-mirror-context.mode` 迁移层已删除；V2.2 不再存在 `native70/java80` 模式选择。

RGI real-maneuver 现在也不再调用旧 `ClusterService.activateCustomRendererPipeline()` / `deactivateCustomRendererPipeline()`。`RendererServer FRAME_READY` 发布 `rgiPresentationActive`，由 `ClusterStateController` 统一完成 ctx72 -> ctx80 与 teardown/release。

本次候选只额外回移 V2.3 已验证的 Luka Layout-derived RGI 几何路径：`ClusterLayerController`、`ClusterGeomOverride`、`CombiMapController` 驱动 planes 98/101/102，并通过 V2.2 `ClusterStateController` 的 view-area seam 重放几何。**未引入** `CarPlayScreenMonitor`、supervisor 或 V2.3 画面检测生命周期；可选 AutoStart 只是 QNX boot hook 调用现有 START helper。

## 2. Fixed production seams

以下值不再允许通过 `config.local` 改写：

```text
capture          = 1024x480 / BGRA
output           = 1440x455
displayable      = 3
HMI state        = /tmp/mmi-mirror-hmi.state
BaseVideo active = /tmp/mmi-mirror-active
BaseVideo ready  = /tmp/mmi-mirror-basevideo.ready
context owner    = Java / ctx80
```

`config.local` 只保留真正需要实车调节的项目：FPS、capture recover、HMI poll、四组 scale/offset、日志路径/大小。旧 `MMI_CONTENT_SCALE/MMI_OFFSET_X/MMI_OFFSET_Y` 仍作为兼容 fallback 保留。

## 3. Exact vehicle-candidate payload

```text
Toolbox/apps/mmi-mirror/
  mmi-mirror-display
  carplay_hook-unified.jar
  maneuver_render-rgi98
  V2.2-SHA256SUMS
  config.local.example
  scripts/
    start_mmi_mirror.sh
    bounded_log.sh
    restore_map.sh
```

三个最终 artifact：

```text
mmi-mirror-display
Size:   254715 bytes
SHA256: 987CAB99FB79B5A45C7A63521805429022790031F98E4305B38233E87E8B3638

carplay_hook-unified.jar
Size:   165385 bytes
SHA256: FA7511B9D6D10BA2A888F03D9B291EF4049FD7DEFA66D4DAF8C56E7C7C4A2C1A
Git blob: 3111df813e0b0ac0a1378ded83b3e7e04301052c
Build:  2026-09-08-354f00b-v2.2
Build source: 354f00bf5710e70f3abfe8c2afffbcff4b462ec5

maneuver_render-rgi98
Size:   113681 bytes
SHA256: 0EF8A2A70E0AA02F595598960F35D82257F7367EB99ACF37566327038C5A9CD8
```

`V2.2-SHA256SUMS` 固定以上三件套。CI 同时检查 exact size/hash、JAR class contract、BAPBridge JAVA80 seam、geometry backport seam、Native no-dmdt contract，因此候选 artifact 在实车验证前不应再次重新编译或替换。

## 4. Stable RGI recovery source

始终保留：

```text
Toolbox/apps/carplay-rgi/
  carplay_hook.jar
  libcarplay_hook.so
  maneuver_render
  flag_atlas.rgba
  Rescue/
```

这些是 stable RGI recovery baseline，不属于残留，MMI cleanup 不修改它们。

## 5. Install behavior

```text
RGI 3/3
  -> snapshot 当前 maneuver_render
  -> 切换到 displayable98 renderer
  -> 安装 Unified JAR + MMI runtime

RGI 0/3
  -> 不安装 RGI98 renderer
  -> 安装 Unified JAR + MMI runtime
  -> ctx80/JAVA ownership 仍存在，MMI displayable3 可工作，只缺 RGI native/displayable98 功能

RGI 1/3 或 2/3
  -> WARNING
  -> 不替换 maneuver_render
  -> 安装 Unified JAR + MMI runtime
```

Installer 的 copy integrity 仍使用 source/destination size equality，并在可用时使用 `cksum`。Unified JAR 不使用固定 expected-size gate。

## 6. Stop / Clear Logs / Uninstall

`Stop MMI Mirror V2.2` 只撤销：

```text
/tmp/mmi-mirror-active
/tmp/mmi-mirror-basevideo.ready
```

Java 根据剩余 RGI demand 决定保留 ctx80 或返回 ctx74。

`Clear temporary MMI Mirror logs` 只删除可丢弃日志和 self-test 临时文件，不删除 controller/HMI/BaseVideo lifecycle 状态。

Uninstall 规则：RGI 0/3 时删除 MMI-owned JAR；RGI > 0 时恢复 stable RGI JAR + stable displayable20 renderer。安装/卸载后仍必须 reboot/HMI restart。

## 7. AutoStart

Green Menu 的 `AutoStart ON/OFF` 管理 `/etc/boot/startup.sh` 中独立的 BEGIN/END block 和 `/mnt/app/eso/hmi/engdefs/scripts/mqb/.mmi_mirror_autostart` marker。

- ON 仅在唯一 `# DCIVIDEO: Kombi Map` boot anchor 后注入 hook，并先备份原文件。
- boot runner 等待已安装 runtime 与 Java controller，再调用正常 `start_mmi_mirror_toolbox.sh`。
- 60 秒内未达到 `/tmp/mmi-mirror-basevideo.ready` 时停止不完整会话。
- OFF 只关闭未来开机启动，不停止当前 session。
- Uninstall 会先移除 hook 与 marker。
- runtime 位于 `/mnt/app`，启用后启动过程不依赖 SD 卡。

## 8. Diagnostics

采集范围：

```text
mmi-mirror-display.log (+ .1)
mmi-mirror-controller.started
mmi-mirror-controller.log
mmi-mirror-hmi.state
mmi-mirror-active
mmi-mirror-basevideo.ready
mmi-mirror-autostart.log / bootstrap.log / status
carplay_java.log (+ .1)
carplay_hook.log (+ .1)
maneuver_render.log (+ .1)
INSTALL_INFO.txt
config.local
runtime_files.txt
processes.txt
dmdt_gc.txt / dmdt_gs.txt   # one-shot diagnostics only
system_info.txt
```

`dmdt` 只允许出现在诊断采集脚本中；Native MMI production source/artifact 不允许包含 context-routing command path。

## 9. Release verification gate

```text
Native source       : PASS - no dmdt / route / reconcile framework
Native artifact     : VERIFIED - exact size/hash, no dmdt command strings
Unified Java source : PASS - no context.mode / readContextMode layer
Unified JAR         : VERIFIED - exact size/hash, class major 46, ownership guard present
Geometry backport   : VERIFIED - Layout-derived 98/101/102 seam, no V2.3 lifecycle
BAPBridge seam      : VERIFIED - no legacy activate/deactivate ctx74 pipeline calls
RGI98 artifact      : VERIFIED / unchanged
Stable RGI baseline : VERIFIED / unchanged
Install/rollback    : static/simulated PASS
CI                  : PASS / GREEN
Vehicle             : P0915 final ctx80 + geometry validation PENDING
```

实车验证通过后，建议将 `main` 直接 fast-forward 到该 exact candidate commit，使最终主分支与实际测试版本保持完全相同。
