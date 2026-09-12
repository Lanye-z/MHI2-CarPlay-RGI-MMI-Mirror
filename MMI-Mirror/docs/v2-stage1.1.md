# V2 / Stage 1.1 implementation notes

## Purpose

V2 keeps the P1404 vehicle-verified BaseVideo data plane intact:

`MMI 1024x480 -> screen_read_display -> GLES -> displayable 3`.

The architectural change is that Cluster/HMI control is now designed to converge on **one unified `carplay_hook.jar` control plane**, while the native renderers stay independent.

Final composition contract:

```text
ctx80={98,101,102,3}

98  = RGI overlay
101 = OEM KDK backing
102 = OEM KDK backing
3   = replaceable BaseVideo plane
      - current: full MMI mirror
      - future: true CarPlay second-screen video
```

The physical migration is deliberately staged so the first V2 vehicle test can still use the already-proven context70 path.

## Four independent geometry profiles

The native binary has four logical states and four independent profiles:

- `CLASSIC_FULL`
- `CLASSIC_SMALL`
- `SPORT_FULL`
- `SPORT_SMALL`

All four currently default to the V1 baseline `scale=0.80, offset=(0,0)`. Even when two profiles use the same initial values, they remain independent so later vehicle tuning is config-only.

The renderer updates only its destination rectangle. Capture, texture ownership, EGL context, native window and displayable 3 are not rebuilt when a profile changes.

## Unified Layout/View observer

`Cluster-HMI/java_overlay/com/luka/carplay/cluster/ClusterStateController.java` is the shared HMI controller prepared for the final single-JAR architecture.

It observes the OEM HMI directly and atomically writes `/tmp/mmi-mirror-hmi.state`:

```text
layout=CLASSIC|SPORT
view=FULL|SMALL
layout_name=<active OEM Layout class>
small_stage_dx=<Layout constant 80>
small_stage_dy=<Layout constant 81>
```

Layout classification follows the same source of truth used by Luka: the active OEM Layout. Sport is recognized from the active layout class / small-stage geometry, and VIEW state is read from `ICoreNaviModelBank.NAV_VIEW_SIZE_CHOICE` (`0=FULL`, `1=SMALL`).

The native reader consumes only `layout` and `view`; extra diagnostic fields are intentionally ignored.

## One Java control plane, native data planes

The final ownership model is:

```text
                    carplay_hook.jar
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
   Layout/View        Context          RGI HMI
     Observer        Controller          Logic
          |                |                |
          +----------------+----------------+
                           |
                    Cluster State
                           |
                 ctx80={98,101,102,3}
```

Native processes only own pixels:

```text
displayable 3  -> BaseVideo renderer
displayable 98 -> RGI renderer
```

Once Java-owned composite mode is enabled, native renderers must not remain competing context writers.

## V2A context mode: `NATIVE70`

The first V2 vehicle validation should keep:

```text
MMI_CONTEXT_OWNER=native70
```

The launcher publishes `/tmp/mmi-mirror-context.mode` as:

```text
NATIVE70
```

Behavior:

- Java writes Layout/View state only.
- Native retains the verified `displayable3 + context70` route.
- Native 250 ms context reconciliation remains available as a temporary safety net.
- Current legacy RGI remains untouched on `displayable20 + context74` whenever Mirror is not active.

This mode exists only to validate automatic Layout/View recognition and the four BaseVideo geometry profiles with minimal vehicle risk.

## Final context mode: `JAVA80`

After the unified Java JAR and context80 composition are built and reviewed, the same native binary can switch to:

```text
MMI_CONTEXT_OWNER=java80
```

The launcher then:

1. writes `JAVA80` to `/tmp/mmi-mirror-context.mode`;
2. launches the native BaseVideo renderer with `--no-route`;
3. disables native context reconciliation;
4. keeps `/tmp/mmi-mirror-active` as session intent.

The native renderer publishes `/tmp/mmi-mirror-basevideo.ready` **only after the first valid MMI frame has been uploaded/presented**.

`ClusterStateController` selects `ctx80` only when both the active marker and ready marker exist. This preserves the proven first-frame-before-route safety rule while moving the context decision into Java.

The Luka-derived `DisplayManagerMIB2High` ownership seam is adapted so the final custom context is:

```text
ctx80={98,101,102,3}
```

and stock physical Cluster context writes are blocked only while `ClusterStateController` has published ownership intent. The controller's own worker is the only accepted context writer during that period.

## BaseVideo readiness seam

The native V2 binary now manages:

```text
/tmp/mmi-mirror-basevideo.ready
```

Lifecycle:

- removed before acquisition starts;
- created after the first valid frame is successfully presented;
- removed before a hard capture recovery / VC restore;
- recreated after capture successfully recovers;
- removed on normal shutdown.

This marker is intentionally independent from `/tmp/mmi-mirror-active`: active means the session wants BaseVideo; ready means a valid plane actually exists and has a frame.

## RGI migration boundary

The current tested RGI package is still the legacy transport:

```text
displayable20 + context74
```

V2A does **not** change that tested path.

The later V2B composite migration will move the RGI renderer to:

```text
displayable98 + context80
```

and connect RGI presentation state to `ClusterStateController.setRgiPresentationActive(...)`.

That migration is intentionally separated from the first Layout/View vehicle validation so failures remain diagnosable.

## Unified JAR build

`Cluster-HMI/build_unified_carplay_hook.sh` builds one Java artifact from:

1. the user's current `Lanye-z/mib2q-carplay-rgi-cn` Java source (RGI business logic remains authoritative), and
2. Luka's latest `DisplayManagerMIB2High` HMI ownership implementation.

The source preparer adapts Luka's composition from `{98,101,102,33}` to `{98,101,102,3}` and replaces `ScreenModule`-specific ownership checks with `ClusterStateController`.

This avoids two JARs overriding the same OEM HMI classes.

## Capture reliability

The V1/fifthBro-derived capture recovery remains: transient readback failures keep the last frame, prolonged failure withdraws BaseVideo readiness, restores the VC (native70 mode) and fully reacquires the MMI source before republishing readiness.

Layout/View observation and context policy remain separate from capture health.

## Build/deployment status

The source-level V2 changes require rebuilding `mmi-mirror-display` with the QNX 6.5 ARMv7 toolchain. The repository's currently packaged `Toolbox/apps/mmi-mirror/mmi-mirror-display` is still the vehicle-tested V1 binary until a V2 artifact is deliberately promoted.

Likewise, the currently packaged `Toolbox/apps/carplay-rgi/carplay_hook.jar` remains the tested legacy RGI binary. `Cluster-HMI` prepares a new unified JAR source/build path but does not silently replace the tested binary.

**Do not vehicle-test the V2 launcher against the old V1 binary.** The old binary does not understand the V2 profile/readiness CLI options.
