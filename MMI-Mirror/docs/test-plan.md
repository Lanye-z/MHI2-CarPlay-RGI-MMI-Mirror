# Stage 1 — MMI Base Video 实车验证计划

## 1. 本轮只验证什么

唯一新增主链：

```text
MMI physical display 1024x480
  -> screen_read_display
  -> VideoFrame
  -> displayable3/context70
  -> VC
```

本轮明确不测试：`displayable98 / RGI / context80 / 101/102 composition / CarPlay 自动生命周期识别 / true second screen`。

## 2. 已知可信底层

保持不变：

```text
VC output        1440x455
displayable      3
context          70
dmdt display     4
restore context  72
stock libdisplayinit.so persistent handle
first-frame-before-route
```

原干净底层已备份在 `backup-clean-display-backend`。

## 3. 推荐第一次运行

```sh
./scripts/start_mmi_mirror.sh
```

默认：`capture 1024x480 / BGRA8888 / 30 FPS / content scale 0.80 / offset 0,0`。

## 4. 通过标准

- 能准确找到 1024x480 physical display；
- 第一帧成功后才切换 VC；
- MMI 菜单/媒体/CarPlay 主画面能同步；
- R/B 颜色正确；
- 画面方向正确；
- 画面比例没有被强制拉伸；
- 30 FPS 附近稳定；
- stride 日志合理；
- Ctrl+C/TERM 后恢复 context72；
- 捕获暂时失败时先恢复，再重新取帧；
- 重获第一帧后可重新进入 base-video context。

## 5. 首次不要求完美的项目

scale、vertical offset、Classic/Sport 两种 layout、VIEW 变化的自动 geometry、hours-long thermal test 都可在链路跑通后再调。

第一轮最重要的是证明 `screen_read_display -> displayable3` 的单进程干净链路成立。

## 6. 故障隔离

找不到 1024x480 display：问题在 `MmiCaptureSource`，VC 此时不应被 route。

有 capture 日志但颜色红蓝互换：尝试 `--capture-format rgba`。

有 capture frame 但 VC 黑屏：临时运行 `./scripts/test_grid.sh`。若 grid 正常，优先查 `VideoFrame/texture upload/geometry`；若 grid 也异常，再查 backend/context。

画面位置不理想：只调 `--content-scale / --offset-x / --offset-y`，不要同时改 capture、displayable 或 context。

## 7. 第二阶段入口

Stage 1 稳定以后才开始：

```text
ctx80={98,101,102,3}
```

并先创建透明 98，只验证 composition；该测试不与本轮混在一起。
