# MHI2Q CarPlay 仪表多层显示开发工作区
这个分支镜像完整 MMI 画面，不区分是否开启 CarPlay；RGI 与 MMI 镜像可以同步运行。现在可通过 Green Menu 单独开启或关闭上车自启动。

本仓库用于 Audi **MHI2Q** Virtual Cockpit 的 CarPlay RGI + BaseVideo 多层显示实验。当前 `v2.2-final-cleanup` 已完成 V2A 迁移框架清理、Native/JAR 重建与静态验收，并回移 V2.3 已验证的 RGI Layout-derived geometry；清理前基线冻结在 `backup-v2.2-pre-final-cleanup-20260907`。当前状态为 **ARTIFACT VERIFIED / VEHICLE PENDING**。

## 最终架构

```text
                    Unified carplay_hook.jar
                              │
             ┌────────────────┼────────────────┐
             ↓                ↓                ↓
        Layout/View       Context          RGI HMI
          observer       controller         bridge
             │                │                │
             └────────────────┼────────────────┘
                              ↓
                       terminal1 / ctx80
                    ctx80={98,101,102,3}
                         │            │
                  displayable98  displayable3
                         │            │
                        RGI       BaseVideo
                                      │
                                 MMI capture
```

固定职责：

```text
Java/HMI     = Layout/View observer + terminal1/ctx80 sole owner
Native RGI   = displayable98 pixels only
Native MMI   = displayable3 pixels only
ctx80        = {98,101,102,3}
```

核心原则：**Java/HMI 控制面统一；Native renderer / 数据源分离；Cluster context 只有一个 writer。**

---

## 已冻结的实车基线

### V1 / Stage 1

冻结分支：`backup-stage1-mmi-mirror-working-20260905`。

已实车验证：MMI 1024x480 capture、GLES BaseVideo renderer、displayable3、ctx70/display4、STOP 恢复原车。

### V2A / NATIVE70

冻结分支：`backup-v2a-vehicle-tested-20260906`；第一轮实车代码基线 `66c805f442b11cf956ff1c0876b05fed72505c6e`。

测试环境：`MHI2Q_CN_AUG22_P0915`，2026-09-06。

```text
Unified JAR + 稳定 RGI           VEHICLE PASS
Unified JAR + MMI BaseVideo      VEHICLE PASS
RGI + MMI 共用同一个 JAR          VEHICLE PASS
displayable3 / ctx70             VEHICLE PASS
安装 / Start / Stop              VEHICLE PASS

Native ctx70 watchdog            VEHICLE FAIL
VIEW retention                   VEHICLE FAIL
```

V2A 日志证明 P0915 上 `dmdt gs` 无有效输出，因此 V2.2 不再保留 Native context ownership 路线。

---

## V2.2 final cleanup

### Native 已变成纯像素层

final-cleanup 已从 Native 源码和最终 ARM artifact 中删除：

```text
/eso/bin/apps/dmdt context command path
route_custom_context / select_context / detect_cluster_context
reconcile_route / restore_context
context/display/restore routing CLI
--no-route / --no-context-reconcile migration switches
Native DisplayStateMachine
Stage1 context ID table
legacy main.cpp
obsolete RGI placeholder interface
```

首帧仍保持原有双 submit：

```text
draw -> swap -> draw -> swap
```

只删除两次 submit 之间在 JAVA80 下已经 no-op 的 Native route 调用。

### Java 不再有 context.mode 迁移层

已删除：

```text
/tmp/mmi-mirror-context.mode
MODE_JAVA80
readContextMode()
isCompositeModeRequested()
lastContextMode
```

最终 ownership 条件：

```text
wantComposite = (BaseVideo active && ready) || RGI frame active
```

Java 仍通过 `IDisplayManager` 完成 `ctx72 bounce -> ctx80`、ctx80 drift reconcile 与空闲时 ctx74 release。

RGI real-maneuver 生命周期也已从旧 `ClusterService.activate/deactivateCustomRendererPipeline()` 的 ctx74/displayable20 gate 解耦：`RendererServer FRAME_READY` 发布 RGI demand，`ClusterStateController` 统一持有/释放 ctx80；`BAPBridge` 不再调用旧 custom-renderer pipeline。

### V2.3 geometry-only backport

为修复 V2.2 与 V2.3 相同的 RGI 箭头位置问题，本分支只回移 V2.3 已验证的 Luka Layout-derived geometry：

```text
CombiMapController
       ↓
ClusterStateController view-area seam
       ↓
ClusterLayerController / ClusterGeomOverride
       ↓
planes 98 / 101 / 102 geometry
```

该回移**不包含** V2.3 `CarPlayScreenMonitor`、supervisor 或画面检测式自动 Start/Stop。当前 AutoStart 仅是独立的 QNX `startup.sh` 启动器，仍调用与 Green Menu 相同的 V2.2 START 路径。

### 固定 production seam

```text
capture          = 1024x480 / BGRA
output           = 1440x455
displayable      = 3
HMI state        = /tmp/mmi-mirror-hmi.state
BaseVideo active = /tmp/mmi-mirror-active
BaseVideo ready  = /tmp/mmi-mirror-basevideo.ready
context owner    = Java / ctx80
```

`config.local` 只保留 FPS、capture recover、HMI poll、四组 scale/offset 与日志配置；旧三项 geometry alias 仅作为已有 config 的兼容 fallback。

---

## Vehicle-candidate artifact set

当前装车候选三件套固定为：

```text
Toolbox/apps/mmi-mirror/mmi-mirror-display
Size:   254715 bytes
SHA256: 987CAB99FB79B5A45C7A63521805429022790031F98E4305B38233E87E8B3638

Toolbox/apps/mmi-mirror/carplay_hook-unified.jar
Size:   165385 bytes
SHA256: FA7511B9D6D10BA2A888F03D9B291EF4049FD7DEFA66D4DAF8C56E7C7C4A2C1A
Git blob: 3111df813e0b0ac0a1378ded83b3e7e04301052c
Build:  2026-09-08-354f00b-v2.2
Build source: 354f00bf5710e70f3abfe8c2afffbcff4b462ec5

Toolbox/apps/mmi-mirror/maneuver_render-rgi98
Size:   113681 bytes
SHA256: 0EF8A2A70E0AA02F595598960F35D82257F7367EB99ACF37566327038C5A9CD8
```

Native 继续使用已静态验证的 final-cleanup artifact；Unified JAR 为 V2.2 JAVA80 + geometry-only backport 的重新构建产物；RGI98 本轮源码未改，继续复用此前 verified artifact。三者由 `Toolbox/apps/mmi-mirror/V2.2-SHA256SUMS` 固定校验。

Stable recovery source 始终保持不变：

```text
Toolbox/apps/carplay-rgi/
  carplay_hook.jar
  libcarplay_hook.so
  maneuver_render
  flag_atlas.rgba
  Rescue/
```

---

## Install / Uninstall ownership

```text
RGI native = 3/3
  -> transactionally snapshot/replace maneuver_render -> displayable98
  -> install Unified JAR + MMI runtime

RGI native = 0/3
  -> do not install RGI98 renderer
  -> install Unified JAR + MMI runtime
  -> Java ctx80 ownership + MMI displayable3 remain available

RGI native = 1/3 or 2/3
  -> WARNING
  -> do not replace maneuver_render
```

Uninstall：

```text
RGI native = 0/3
  -> remove MMI-owned carplay_hook.jar

RGI native > 0
  -> restore stable RGI carplay_hook.jar
  -> restore stable displayable20 maneuver_render
```

安装或卸载后必须 reboot/HMI restart，再使用 RGI 或启动 MMI Mirror。

---

## 上车自启动

先完成 `Install/Update MMI Mirror V2.2`，可紧接着在 Green Menu 选择 `AutoStart ON`，然后执行安装流程要求的完整重启：

```text
AutoStart ON  - 写入带 BEGIN/END 标记的 startup.sh hook
AutoStart OFF - 删除 hook 与持久 marker，仅保留手动启动
```

AutoStart hook 注入 `/etc/boot/startup.sh` 中唯一的 `# DCIVIDEO: Kombi Map` 锚点；找不到或发现多个锚点时会拒绝修改。开机 runner 最多等待 120 秒让已安装 runtime 与 Java controller 就绪，然后调用同一个 `start_mmi_mirror_toolbox.sh`。启动后 60 秒内未出现 BaseVideo ready marker，会自动停止不完整会话。

runtime 已安装到 `/mnt/app/root/mmi-mirror`，因此启用后开机运行不依赖 SD 卡持续插入。`AutoStart OFF` 不停止当前会话；若要立即停止，请另选 `Stop MMI Mirror V2.2`。卸载程序会先清理 AutoStart hook。

诊断文件：

```text
/tmp/mmi-mirror-autostart-bootstrap.log
/tmp/mmi-mirror-autostart.log
/tmp/mmi-mirror-autostart.status
Backup/<firmware>/MMIMirror/AutoStart/
```

---

## Release verification status

```text
Native source cleanup                 PASS
Native ARM artifact                   VERIFIED
Unified Java source cleanup           PASS
Unified JAR                           VERIFIED
Geometry-only backport                VERIFIED
BAPBridge JAVA80 / no legacy ctx74    VERIFIED
RGI98 renderer                        VERIFIED / unchanged
Stable RGI recovery baseline          VERIFIED / unchanged
Install/Uninstall/Rollback simulation PASS
CI release gate                       PASS / GREEN
P0915 final ctx80 + geometry vehicle  PENDING
```

当前发布规则：**候选 artifact 在实车验证前不得再重新编译或替换。** 实车通过后可将 `main` 直接 fast-forward 到该已验证 commit，使 `main` 与上车测试版本保持同一 tree/artifact。

---

## Clear Logs / Stop

运行状态文件：

```text
/tmp/mmi-mirror-controller.started
/tmp/mmi-mirror-hmi.state
/tmp/mmi-mirror-active
/tmp/mmi-mirror-basevideo.ready
```

`Clear temporary MMI Mirror logs` 只删除可丢弃日志/self-test/AutoStart 日志，不改变 lifecycle 或 AutoStart 开关状态。需要释放 BaseVideo ownership 时使用 `Stop MMI Mirror V2.2`；Java 根据剩余 RGI demand 决定保留 ctx80 或返回 ctx74。

---

## 最终实车验证项目

```text
1. 使用上述 exact artifact set
2. Install -> reboot/HMI restart
3. Unified JAR 正常加载；controller.started 生成
4. observer 正确产生 CLASSIC/SPORT + FULL/SMALL
5. MMI displayable3 + BaseVideo ready
6. Java ctx72 bounce -> ctx80
7. VIEW 后物理 VC 保持 ctx80
8. RGI 使用 displayable98
9. RGI 箭头位置随 FULL/SMALL geometry 正确
10. RGI real-maneuver 不再触发 legacy ctx74 gate
11. RGI + MMI 同时存在于 ctx80={98,101,102,3}
12. route start/stop 无独立 Native context 抢占
13. MMI stop / capture loss / RGI end 正确释放或保持 ownership
14. Uninstall -> reboot -> stable RGI20/JAR 恢复
```

## 关键文档

- [`Toolbox/apps/mmi-mirror/README.md`](Toolbox/apps/mmi-mirror/README.md) — SD payload / lifecycle / artifact manifest
- [`MMI-Mirror/docs/v2.2-design.md`](MMI-Mirror/docs/v2.2-design.md) — V2.2 final design
- [`Cluster-HMI/README.md`](Cluster-HMI/README.md) — Unified Java control plane
- [`MMI-Mirror/docs/v2-stage1.1.md`](MMI-Mirror/docs/v2-stage1.1.md) — V2A 历史归档
- [`docs/upstream-toolbox-README.md`](docs/upstream-toolbox-README.md) — 原 Toolbox README
