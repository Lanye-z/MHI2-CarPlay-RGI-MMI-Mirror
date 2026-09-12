# MHI2Q CarPlay 仪表多层显示框架 — 最终架构与 Stage 1 实现

## 1. 最终目标

最终显示模型固定为：

```text
                    CarPlay / HU
                        │
          ┌─────────────┴─────────────┐
          │                           │
   BaseVideoSource                RGI pipeline
          │                           │
   ┌──────┴────────┐                  │
   │               │                  │
MMI capture   True second screen      │
(Stage 1)        (future)              │
   │               │                  │
   └──────┬────────┘                  │
          ▼                           ▼
 displayable 3                  displayable 98
          │                           │
          └────────────┬──────────────┘
                       ▼
             context 80 composition
               {98,101,102,3}
                       │
                       ▼
                      VC
```

所有权：

```text
20 / 33     stock-owned, never rebound
3 / 98      custom-owned
101 / 102   stock KDK backing reused
```

## 2. 为什么 Stage 1 不直接上 context 80

Stage 1 的第一次实车目标只验证：

```text
screen_read_display
  ↓
VideoFrame
  ↓
displayable3/context70
  ↓
VC
```

`displayable3/context70/display4` 已经通过旧 Stage-2 grid/VNC 实车验证，因此新增变量只有 MMI capture。

待该链路稳定后再验证：

```text
context80={98,101,102,3}
```

且先让 98 全透明，把“多 plane composition”与“RGI 数据/渲染”分开测试。

## 3. 模块边界

### `video_frame.h`
统一帧描述，不绑定 MMI：`data / width / height / stride / pixel format / timestamp`。

### `cluster_video_source.h`
抽象 Base Video source。Stage 1 实现 `MmiCaptureSource`；未来 second screen 只新增另一个 source。

### `mmi_capture_source.*`
只负责 QNX Screen 取帧：physical display discovery、pixmap/buffer、`screen_read_display` 和 frame metadata；不负责显示、context 或颜色转换策略。

### `gl_renderer.*`
负责 stride pack、BGRA/RGBA shader swizzle、texture upload 和 GPU scale/position。

### `cluster_video_display.*`
统一 `VideoFrame -> displayable 3`，内部保留 `Mhi2qBackend + GlRenderer + first-frame-before-route + restore/shutdown`。

### `display_state_machine.*`
纯状态策略：`STOCK / BASE_VIDEO / BASE_VIDEO_RGI`；不直接调用 QNX、EGL 或 Java DisplayManager。

### `rgi_overlay_controller.h`
最终 RGI 抽象接口，占位但不在 Stage 1 运行。后续实现应对应 Luka 的 displayable 98。

## 4. Context / displayable 规划

Stage 1 实车基线：

```text
displayable 3
context 70
dmdt display 4
restore 72
```

最终 OEM 状态：`ctx74`，其中 `20=stock RGI`、`33=stock native map`。

最终 CarPlay 状态：

```text
ctx80 = {98,101,102,3}
```

z-order 为 index 0 在前：`98 RGI -> 101/102 backing -> 3 base video`。

## 5. 最终状态机

输入：`session_active / base_video_ready / guidance_active`。

输出：

```text
!session || !base_ready -> STOCK
session + base_ready    -> BASE_VIDEO
... + guidance          -> BASE_VIDEO_RGI
```

Stage 1 的 `--mmi` 是显式手工 session，只驱动前两个状态。后续 fifthBro-style CarPlay lifecycle detector 将替换这个手工输入。

## 6. Base Video 可替换性

今天：`MmiCaptureSource -> VideoFrame -> ClusterVideoDisplay -> displayable3`。

未来：`CarPlaySecondScreenSource -> VideoFrame -> ClusterVideoDisplay -> displayable3`。

后半段不变，因此真正 second screen 接入时不需要重新设计 displayable、context 或 RGI。

## 7. Stage 1 取帧实现

采用 MHI2Q/P1404 已跑通的 Screen 参数：`DISPLAY_MANAGER_CONTEXT`（失败则 `WINDOW_MANAGER_CONTEXT`）、精确 1024x480 physical display、RGBA8888 pixmap、READ|NATIVE、`screen_read_display()`。

默认把 buffer 标记为 BGRA8888；shader 交换 R/B。Stride 非 packed 时，renderer 仅逐行 pack，不做 CPU 全帧色彩转换。

## 8. 第一帧与恢复

首次：

```text
capture init
  ↓
first screen_read_display succeeds
  ↓
create displayable3/EGL
  ↓
upload/draw/swap
  ↓
route context70
  ↓
draw/swap again
```

捕获连续失败：

```text
restore context72
  ↓
destroy/recreate CaptureSource
  ↓
wait for a new valid first frame
  ↓
re-route context70
```

这保证 capture 故障不会让 VC 长时间停在空 surface。

## 9. 后续阶段

1. Stage 1 实车验证 MMI Base Video；
2. 长时间稳定与 geometry tuning；
3. 定义/切换 context80，98 保持透明；
4. 接入 Luka RGI 98 + layout/view policy；
5. 接入真实 CarPlay session detector；
6. 用 true second-screen source 替换 MMI source。
