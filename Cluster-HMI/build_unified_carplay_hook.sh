#!/bin/bash
# Build the unified carplay_hook.jar containing:
#   - the user's current RGI/Amap Java implementation
#   - ClusterStateController diagnostics + final JAVA80 ownership
#   - BAPBridge detached from legacy ClusterService ctx74/displayable20 routing
#   - Luka-derived DisplayManagerMIB2High ownership guard
#   - Luka-derived ClusterLayerController / ClusterGeomOverride / CombiMapController geometry
#   - ctx80={98,101,102,3}
#
# Developer-side build only. It does NOT run on the MHI2Q unit.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RGI_SOURCE_DIR="${RGI_SOURCE_DIR:-$ROOT_DIR/../mib2q-carplay-rgi-cn}"
LUKA_SOURCE_DIR="${LUKA_SOURCE_DIR:-$ROOT_DIR/../mib2q-carplay-rgi}"
TOOLS_DIR="${JXE2JAR_DIR:-$ROOT_DIR/../jxe2jar}"
EXPECTED_RGI_REV="${EXPECTED_RGI_REV:-0c77063b824bcb2368740c483e5bbc5204cb0816}"
EXPECTED_LUKA_REV="${EXPECTED_LUKA_REV:-ab93a6c7c6976b667b75133da7f3ef057dd4dce8}"
ALLOW_SOURCE_DRIFT="${ALLOW_SOURCE_DRIFT:-0}"

DEFAULT_JAVA_HOME="$TOOLS_DIR/jvms/zulu8.78.0.19-ca-jdk8.0.412-macosx_aarch64/zulu-8.jdk/Contents/Home"
JAVA_HOME="${JAVA_HOME:-$DEFAULT_JAVA_HOME}"
JAVAC="${JAVAC:-$JAVA_HOME/bin/javac}"
JAR="${JAR:-$JAVA_HOME/bin/jar}"
LSD_JAR="${LSD_JAR:-$TOOLS_DIR/out/lsd.jar}"
OSGI_LIBS="${OSGI_LIBS:-$TOOLS_DIR/libs}"
OSGI_CP="$OSGI_LIBS/org.osgi.framework-1.10.0.jar:$OSGI_LIBS/org.osgi.util.tracker-1.5.4.jar"
RGI_BASE_JAR="${RGI_BASE_JAR:-$RGI_SOURCE_DIR/release/carplay_hook.jar}"

BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build}"
SRC_DIR="$BUILD_DIR/src"
CLASS_DIR="$BUILD_DIR/classes"
EMPTY_SOURCEPATH="$BUILD_DIR/empty-sourcepath"
OUTPUT_JAR="${JAVA_OUTPUT:-$BUILD_DIR/carplay_hook-unified.jar}"
PREPARE="$SCRIPT_DIR/tools/prepare_unified_sources.py"
GEOMETRY_OVERLAY="$SCRIPT_DIR/tools/apply_rgi_geometry.py"
CONTROLLER="$SCRIPT_DIR/java_overlay/com/luka/carplay/cluster/ClusterStateController.java"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$RGI_SOURCE_DIR/java_patch" ] || fail "RGI source tree not found: $RGI_SOURCE_DIR"
[ -f "$LUKA_SOURCE_DIR/java_patch/de/audi/tghu/fwhmi/DisplayManagerMIB2High.java" ] || fail "Luka HMI source tree not found: $LUKA_SOURCE_DIR"
[ -f "$LUKA_SOURCE_DIR/java_patch/com/luka/carplay/cluster/ClusterLayerController.java" ] || fail "Luka ClusterLayerController source not found"
[ -f "$LUKA_SOURCE_DIR/java_patch/com/luka/carplay/cluster/ClusterGeomOverride.java" ] || fail "Luka ClusterGeomOverride source not found"
[ -f "$LUKA_SOURCE_DIR/java_patch/de/esolutions/hmi/widgets/audi/evo/high/widgets/CombiMapController.java" ] || fail "Luka CombiMapController source not found"
[ -x "$JAVAC" ] || fail "javac not found: $JAVAC"
[ -x "$JAR" ] || fail "jar not found: $JAR"
[ -f "$LSD_JAR" ] || fail "lsd.jar not found: $LSD_JAR"
[ -f "$RGI_BASE_JAR" ] || fail "pinned RGI base JAR not found: $RGI_BASE_JAR"
[ -f "$OSGI_LIBS/org.osgi.framework-1.10.0.jar" ] || fail "missing OSGi framework jar"
[ -f "$OSGI_LIBS/org.osgi.util.tracker-1.5.4.jar" ] || fail "missing OSGi tracker jar"
[ -f "$PREPARE" ] || fail "missing source preparer: $PREPARE"
[ -f "$GEOMETRY_OVERLAY" ] || fail "missing geometry overlay: $GEOMETRY_OVERLAY"
[ -f "$CONTROLLER" ] || fail "missing controller source: $CONTROLLER"
command -v git >/dev/null 2>&1 || fail "git is required to verify source revisions"

if [ -n "${PYTHON:-}" ]; then
  "$PYTHON" -c 'import sys' >/dev/null 2>&1 || fail "Python interpreter is not usable: $PYTHON"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
  PYTHON=python
else
  fail "Python 3 is required (set PYTHON to a working interpreter on Windows)"
fi

RGI_REV="$(git -C "$RGI_SOURCE_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
LUKA_REV="$(git -C "$LUKA_SOURCE_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$ALLOW_SOURCE_DRIFT" != "1" ]; then
  [ "$RGI_REV" = "$EXPECTED_RGI_REV" ] || fail "RGI source revision drift: expected $EXPECTED_RGI_REV, got $RGI_REV"
  [ "$LUKA_REV" = "$EXPECTED_LUKA_REV" ] || fail "Luka source revision drift: expected $EXPECTED_LUKA_REV, got $LUKA_REV"
fi

echo "RGI source revision:  $RGI_REV"
echo "Luka source revision: $LUKA_REV"

rm -rf "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$CLASS_DIR" "$EMPTY_SOURCEPATH" "$(dirname "$OUTPUT_JAR")"

"$PYTHON" "$PREPARE" \
  --rgi-source "$RGI_SOURCE_DIR" \
  --luka-source "$LUKA_SOURCE_DIR" \
  --output-src "$SRC_DIR" \
  --controller-source "$CONTROLLER"

# Backport only the V2.3 geometry fix. This adds Luka's current Layout-derived
# planes 98/101/102 controller and view-area feed to the already-prepared
# JAVA80 tree. No CarPlayScreenMonitor or V2.3 process lifecycle is included.
"$PYTHON" "$GEOMETRY_OVERLAY" \
  --src-dir "$SRC_DIR" \
  --luka-source "$LUKA_SOURCE_DIR"

AMAP_OVERLAY="$RGI_SOURCE_DIR/tools/apply_v38_amap_overlay.py"
if [ -f "$AMAP_OVERLAY" ] && [ -f "$SRC_DIR/com/luka/carplay/routeguidance/AmapV38Compat.java" ]; then
  AMAP_JAVA="$SRC_DIR/com/luka/carplay/routeguidance/AmapV38Compat.java"
  "$PYTHON" - "$AMAP_JAVA" <<'PY'
import io, sys
path = sys.argv[1]
with io.open(path, 'r', encoding='utf-8', newline=None) as f:
    text = f.read()
seed = ("    private void seedFromRaw() {\n"
        "        int head = raw.head();\n"
        "        int ver = raw.value(raw.mVer, head, -1);")
seed_marked = ("    private void seedFromRaw() {\n"
               "        int head = raw.head(); /* build-only overlay anchor marker */\n"
               "        int ver = raw.value(raw.mVer, head, -1);")
if text.count(seed) != 1:
    raise SystemExit("ERROR: expected one seedFromRaw overlay anchor, found %d" % text.count(seed))
text = text.replace(seed, seed_marked, 1)
with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(text)
PY
  "$PYTHON" "$AMAP_OVERLAY" --java "$AMAP_JAVA"
fi

BUILD_ID="$(date +%Y-%m-%d)-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo nogit)-"
HOOK_FILE="$SRC_DIR/com/luka/carplay/CarPlayHook.java"
if [ -f "$HOOK_FILE" ]; then
  "$PYTHON" - "$HOOK_FILE" "$BUILD_ID" <<'PY'
import io, sys
path, build = sys.argv[1], sys.argv[2]
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()
text = text.replace('@BUILD_ID@', build)
with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(text)
PY
fi

CORE_SOURCES_LIST="$BUILD_DIR/sources-core.txt"
BAP_SOURCE='./com/luka/carplay/routeguidance/BAPBridge.java'
printf '%s\n' \
  './com/luka/carplay/CarPlayHook.java' \
  './com/luka/carplay/routeguidance/RendererServer.java' \
  './com/luka/carplay/routeguidance/AmapV38Compat.java' \
  './com/luka/carplay/cluster/ClusterStateController.java' \
  './com/luka/carplay/cluster/ClusterGeomOverride.java' \
  './com/luka/carplay/cluster/ClusterLayerController.java' \
  './de/audi/tghu/fwhmi/DisplayManagerMIB2High.java' \
  './de/esolutions/hmi/widgets/audi/evo/high/widgets/CombiMapController.java' \
  > "$CORE_SOURCES_LIST"
while IFS= read -r source; do
  [ -f "$SRC_DIR/${source#./}" ] || fail "missing selected unified source: $source"
done < "$CORE_SOURCES_LIST"
[ -f "$SRC_DIR/${BAP_SOURCE#./}" ] || fail "missing selected unified source: $BAP_SOURCE"

CORE_COUNT="$(wc -l < "$CORE_SOURCES_LIST" | tr -d ' ')"
echo "Compiling ${CORE_COUNT} core Java files against real MHI2Q lsd.jar first (source/target 1.2)..."

(
  cd "$SRC_DIR"
  "$JAVAC" -encoding UTF-8 -source 1.2 -target 1.2 \
    -cp "$LSD_JAR:$OSGI_CP:$RGI_BASE_JAR" \
    -sourcepath "$EMPTY_SOURCEPATH" \
    -d "$CLASS_DIR" \
    -Xlint:-options \
    @"$CORE_SOURCES_LIST"
)

# BAPBridge is part of the pinned RGI patch and calls four ClusterService
# accessors added by that patch. Compile only BAPBridge with the just-built
# classes first, then the exact pinned RGI base JAR, then the real
# lsd.jar for the remaining platform APIs. The core classes above keep
# real-MHI2Q lsd.jar first for their API gate.
echo "Compiling BAPBridge against pinned RGI ClusterService API + real MHI2Q platform APIs..."
(
  cd "$SRC_DIR"
  "$JAVAC" -encoding UTF-8 -source 1.2 -target 1.2 \
    -cp "$CLASS_DIR:$RGI_BASE_JAR:$LSD_JAR:$OSGI_CP" \
    -sourcepath "$EMPTY_SOURCEPATH" \
    -d "$CLASS_DIR" \
    -Xlint:-options \
    "$BAP_SOURCE"
)

# ClusterService stays byte-for-byte from the pinned RGI base JAR. The JAVA80
# context seam is implemented in the rebuilt BAPBridge instead.
cp "$RGI_BASE_JAR" "$OUTPUT_JAR"
"$JAR" uf "$OUTPUT_JAR" -C "$CLASS_DIR" .

printf '%s\n' \
  "Built Current: $OUTPUT_JAR" \
  "Build ID: $BUILD_ID" \
  "RGI rev: $RGI_REV" \
  "Luka rev: $LUKA_REV" \
  "ctx80: {98,101,102,3}" \
  "ownership: JAVA80 / ClusterStateController single writer" \
  "rgi-pipeline: FRAME_READY -> controller; no legacy BAPBridge ctx74 pipeline calls" \
  "rgi-geometry: Luka Layout-derived 98/101/102 geometry backported from V2.3" \
  "lifecycle: unchanged; no V2.3 CarPlayScreenMonitor/auto lifecycle" \
  "bap-compile: core=real-lsd-first; BAPBridge=pinned-RGI-ClusterService-first" \
  "diagnostics: /tmp/mmi-mirror-controller.log"
