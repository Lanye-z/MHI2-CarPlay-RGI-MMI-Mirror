# MHI2Q MMI Mirror V2.2 / JAVA80 BaseVideo data plane

本目录是 `displayable3` BaseVideo 的 Native 工程。V2.2 final-cleanup 的职责已经固定：**Native 只负责 pixels；Java `ClusterStateController` 是 terminal1/ctx80 唯一 context writer。**

```text
ctx80 = {98,101,102,3}

98      = RGI overlay
101/102 = OEM KDK backing
3       = BaseVideo
          ├─ current: full MMI mirror
          └─ future: CarPlay second-screen video
```

## V2A 历史基础

V1/V2A 已经实车验证 MMI 1024x480 capture、GLES2 与 displayable3，并证明基于 `dmdt gs` 的 Native context watchdog 不适合作为 P0915 的最终 ownership 机制。历史路线保存在冻结分支和 `docs/v2-stage1.1.md`；不再属于当前 production source。

## V2.2 Native contract

final-cleanup 已从 Native 源码删除：

```text
dmdt gs/sc/dc command path
route / reconcile / restore context framework
context/display/restore routing CLI
--no-route / --no-context-reconcile migration switches
Native DisplayStateMachine
Stage1 context-ID table
legacy main.cpp
obsolete RGI placeholder interface
```

Native 保留：

```text
1024x480 BGRA MMI capture
GLES rendering
1440x455 displayable3 output
4 geometry profiles
/tmp/mmi-mirror-basevideo.ready
capture failure/recovery
```

首帧仍保持此前的双 submit：

```text
draw -> swap -> draw -> swap
```

只移除了两次 submit 之间原本在 JAVA80 下已经 no-op 的 Native route 调用。

## Fixed Java/Native seams

```text
/tmp/mmi-mirror-hmi.state
/tmp/mmi-mirror-active
/tmp/mmi-mirror-basevideo.ready
```

这些路径以及 capture/output/displayable 不再通过 `config.local` 改写，避免 Java 和 Native 使用不同 seam。

可调项目仅包括：FPS、capture recover、HMI poll、四组 geometry scale/offset、日志参数。旧三项 geometry alias 仍作为已有配置兼容 fallback。

## Capture recovery

```text
短时 screen_read_display() failure
  -> freeze last valid frame

持续 failure 超过 capture_recover_ms
  -> withdraw BaseVideo ready
  -> reacquire physical MMI source
  -> valid frame 后重新发布 ready
```

这是视频数据源 watchdog，与 Cluster context ownership 完全分离。

## Build

Windows + QNX SDP 6.5：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
```

或使用 QNX 环境中的 `Makefile/build_qnx.sh`。

构建输出：

```text
MMI-Mirror/build/mmi-mirror-display
```

`build_windows.ps1` 不会自动覆盖 Toolbox promotion artifact，并会检查重建二进制是否包含被禁止的 Native context-routing command strings。

## Vehicle-candidate Native artifact

当前已 promotion 并用于最终实车验证的 Native：

```text
Toolbox/apps/mmi-mirror/mmi-mirror-display
Size:   254715 bytes
SHA256: 987CAB99FB79B5A45C7A63521805429022790031F98E4305B38233E87E8B3638
ELF:    ARM32 EABI5
Interp: /usr/lib/ldqnx.so.2
```

静态验收要求与结果：

```text
ARM32 / QNX loader                         PASS
no dynamic libstdc++.so                    PASS
no /eso/bin/apps/dmdt context command path PASS
no dmdt gs/sc/dc strings                   PASS
no route/reconcile implementation          PASS
Native pixel-only contract                 PASS
```

该 artifact 已由 final-cleanup 源码重新构建。**在本轮 P0915 实车验证结束前不要再次重编或替换它。**

最终 manifest：

```text
Toolbox/apps/mmi-mirror/V2.2-SHA256SUMS
```

最终装车流程与恢复边界见：

- `Toolbox/apps/mmi-mirror/README.md`
- `docs/v2.2-design.md`
