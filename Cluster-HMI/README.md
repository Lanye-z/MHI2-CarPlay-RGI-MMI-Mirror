# Cluster-HMI unified control plane

This directory builds the **single Java/HMI context owner** used by MMI Mirror / CarPlay RGI V2.2 final-cleanup.

## Final contract

```text
                    Unified carplay_hook.jar
                              |
             +----------------+----------------+
             |                |                |
             v                v                v
        Layout/View       Context          RGI HMI
          observer       controller         bridge
             |                |                |
             +----------------+----------------+
                              |
                       terminal1 / ctx80
                    ctx80={98,101,102,3}
                         |            |
                  displayable98  displayable3
                         |            |
                        RGI       BaseVideo
```

The separation is fixed:

- Java `ClusterStateController` owns terminal1 context lifecycle.
- `DisplayManagerMIB2High` guards non-owner physical Cluster context writes.
- Native RGI renders displayable98 pixels only.
- Native MMI renders displayable3 pixels only.
- There is no `native70/java80` production mode switch and no `/tmp/mmi-mirror-context.mode` seam.

## Context policy

```text
wantComposite = (BaseVideo active && BaseVideo ready) || RGI presentation active
```

Java controller behavior:

```text
wantComposite
  -> ownership intent
  -> ctx72 bounce
  -> ctx80

no BaseVideo/RGI demand
  -> release ownership
  -> ctx74
```

A low-cost `IDisplayManager.getCurrentContextID(1)` reconcile remains in Java. Native shell/dmdt context polling is not part of V2.2 final-cleanup.

The RGI real-maneuver lifecycle is also detached from the legacy `ClusterService.activateCustomRendererPipeline()` / `deactivateCustomRendererPipeline()` ctx74/displayable20 path. `RendererServer` publishes RGI presentation state and `ClusterStateController` owns the physical ctx80 transition/release.

## Shared state seams

```text
/tmp/mmi-mirror-hmi.state
/tmp/mmi-mirror-active
/tmp/mmi-mirror-basevideo.ready
/tmp/mmi-mirror-controller.started
/tmp/mmi-mirror-controller.log
```

The state file carries CLASSIC/SPORT + FULL/SMALL observer output. `active + ready` are BaseVideo demand. RGI demand is held directly by `ClusterStateController.rgiPresentationActive`.

## Source composition

The build keeps two pinned upstream source-of-truth trees:

1. `Lanye-z/mib2q-carplay-rgi-cn` — current RGI/Amap Java implementation.
2. Luka MHI2Q source — `DisplayManagerMIB2High` ownership implementation.

`tools/prepare_unified_sources.py`:

- starts from the pinned user RGI Java source;
- adds the final `ClusterStateController`;
- adapts Luka's DisplayManager ownership guard;
- fixes the composite displayable set to `ctx80={98,101,102,3}`;
- injects RGI presentation-active seams into the existing RendererServer lifecycle;
- patches generated `BAPBridge` so no legacy ClusterService custom-renderer pipeline calls remain.

## Build

Developer machine only:

```bash
RGI_SOURCE_DIR=/path/to/mib2q-carplay-rgi-cn \
LUKA_SOURCE_DIR=/path/to/mib2q-carplay-rgi \
JXE2JAR_DIR=/path/to/jxe2jar \
./Cluster-HMI/build_unified_carplay_hook.sh
```

Output:

```text
Cluster-HMI/build/carplay_hook-unified.jar
```

The build uses `-source 1.2 -target 1.2` with a **two-stage javac gate**:

```text
Stage 1 / five core sources:
  classpath = real lsd.jar : OSGi : pinned RGI base JAR

Stage 2 / BAPBridge only:
  classpath = generated classes : pinned RGI base JAR : real lsd.jar : OSGi
```

This keeps real MHI2Q APIs authoritative for the core classes while allowing `BAPBridge` to resolve the four patched `ClusterService` accessors that exist only in the pinned RGI base JAR. `ClusterService.java` is not recompiled; final `ClusterService.class` is inherited byte-for-byte from the pinned RGI base JAR.

## Vehicle-candidate Unified JAR

The repaired JAVA80 RGI seam has been rebuilt and promoted to:

```text
Toolbox/apps/mmi-mirror/carplay_hook-unified.jar
Size:   150064 bytes
SHA256: 91E2ACCECBC03226D181AB0BA5E272A2CDCB24D70B183BFF3CF1315B3EB79429
Build:  2026-09-08-9fa250f-v2.2
Build source: 9fa250f49a9deb9cb8394e279c7f98e17aab2e4f
```

Release checks require:

```text
JAR integrity / no duplicate entries           PASS
59 class files                                 PASS
class major 46                                 PASS
ClusterStateController present                 PASS
no mmi-mirror-context.mode / readContextMode   PASS
DisplayManager ownership guard present         PASS
ctx80={98,101,102,3} composition               PASS
BAPBridge no legacy activate/deactivate calls  PASS
JAVA80 pipeline marker / RGI state seam        PASS
ClusterService inherited byte-for-byte         PASS
```

The exact vehicle-candidate hash is pinned in `Toolbox/apps/mmi-mirror/V2.2-SHA256SUMS` and CI. **Do not rebuild or replace this JAR before the current vehicle validation completes.**

## Recovery boundary

Do not overwrite the stable RGI recovery baseline under:

```text
Toolbox/apps/carplay-rgi/
```

The MMI-owned Unified JAR belongs only under `Toolbox/apps/mmi-mirror/` before the installer transaction copies it to the vehicle. Stable RGI recovery payloads remain the rollback source.

Historical V2A staging details are kept in `MMI-Mirror/docs/v2-stage1.1.md` and the frozen V2A branches; they are not part of the current production contract.
