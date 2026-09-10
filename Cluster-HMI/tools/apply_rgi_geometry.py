#!/usr/bin/env python3
"""Backport the V2.3 Luka-derived RGI geometry fix onto the JAVA80 build.

This intentionally does NOT import any V2.3 CarPlay auto-lifecycle code.
It only adds the same Layout-derived planes 98/101/102 geometry path that was
vehicle-tested in V2.3:
  - ClusterLayerController
  - ClusterGeomOverride
  - CombiMapController
  - the minimal ClusterStateController seams required by those classes

The input source tree is the already-prepared build copy. All edits are
anchor-checked so source drift fails loudly instead of producing a partial JAR.
"""

from __future__ import print_function
import argparse
import os
import shutil
import sys


def fail(msg):
    print("ERROR: " + msg, file=sys.stderr)
    raise SystemExit(2)


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_text(path, text):
    parent = os.path.dirname(path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        fail("%s: expected exactly one match, found %d" % (label, count))
    return text.replace(old, new, 1)


def replace_required(text, old, new, label, minimum=1):
    count = text.count(old)
    if count < minimum:
        fail("%s: expected at least %d match(es), found %d" % (label, minimum, count))
    return text.replace(old, new)


def patch_cluster_layer(src):
    """Adapt Luka's current 98/101/102 geometry controller to JAVA80."""
    text = read_text(src)
    text = replace_required(
        text,
        "com.luka.carplay.core.ScreenModule.isSmallScreenViewArea()",
        "com.luka.carplay.cluster.ClusterStateController.isSmallScreenViewArea()",
        "ClusterLayerController view-area seam")
    text = replace_required(
        text,
        "com.luka.carplay.core.ScreenModule.isConnected()",
        "com.luka.carplay.cluster.ClusterStateController.isClusterOwned()",
        "ClusterLayerController ownership seam")
    text = replace_required(
        text,
        "com.luka.carplay.core.ScreenModule.isNavActive()",
        "com.luka.carplay.cluster.ClusterStateController.isRgiPresentationActive()",
        "ClusterLayerController RGI seam")
    text = text.replace("dc[80] = {98,101,102,33}", "dc[80] = {98,101,102,3}")
    return text


def patch_combi_map(src):
    """Keep Luka's stock-layout geometry feed but route state to JAVA80."""
    text = read_text(src)
    text = replace_required(
        text,
        "com.luka.carplay.core.ScreenModule.setViewAreaMode(",
        "com.luka.carplay.cluster.ClusterStateController.setViewAreaMode(",
        "CombiMapController view-area seam")
    text = replace_required(
        text,
        "com.luka.carplay.core.ScreenModule.VIEWAREA_SMALLSCREEN",
        "com.luka.carplay.cluster.ClusterStateController.VIEWAREA_SMALLSCREEN",
        "CombiMapController small-view constant seam")
    text = replace_required(
        text,
        "com.luka.carplay.core.ScreenModule.VIEWAREA_FULLSCREEN",
        "com.luka.carplay.cluster.ClusterStateController.VIEWAREA_FULLSCREEN",
        "CombiMapController fullscreen constant seam")
    text = replace_required(
        text,
        "com.luka.carplay.core.ScreenModule.isConnected()",
        "com.luka.carplay.cluster.ClusterStateController.isClusterOwned()",
        "CombiMapController ownership seam")
    return text


def patch_cluster_state_controller(src):
    """Add only the seams required by Luka geometry; keep context policy."""
    text = read_text(src)

    anchor = (
        "    public static final int CTX_STOCK = 74;\n"
        "    public static final int CTX_BOUNCE = 72;\n"
        "    public static final int CTX_COMPOSITE = 80;\n"
    )
    inject = anchor + (
        "\n"
        "    public static final int VIEWAREA_FULLSCREEN = 0;\n"
        "    public static final int VIEWAREA_SMALLSCREEN = 1;\n"
    )
    text = replace_once(text, anchor, inject, "ClusterStateController view constants")

    anchor = "    private static volatile boolean rgiPresentationActive;\n"
    inject = (
        "    private static volatile boolean rgiPresentationActive;\n"
        "    private static volatile boolean smallScreenViewArea;\n"
    )
    text = replace_once(text, anchor, inject, "ClusterStateController view state")

    anchor = (
        "    public static boolean isContextWriterThread() {\n"
        "        return Thread.currentThread() == contextWriterThread;\n"
        "    }\n"
    )
    inject = anchor + (
        "\n"
        "    public static boolean isSmallScreenViewArea() {\n"
        "        return smallScreenViewArea;\n"
        "    }\n"
        "\n"
        "    /** View-size seam used by Luka's RGI plane geometry controller. */\n"
        "    public static void setViewAreaMode(int mode) {\n"
        "        boolean small = mode == VIEWAREA_SMALLSCREEN;\n"
        "        if (smallScreenViewArea == small) return;\n"
        "        smallScreenViewArea = small;\n"
        "        try { com.luka.carplay.cluster.ClusterLayerController.reapply(); }\n"
        "        catch (Throwable t) { diag(\"WARN geometry reapply on view change failed: \" + describe(t)); }\n"
        "    }\n"
    )
    text = replace_once(text, anchor, inject, "ClusterStateController view methods")

    anchor = (
        "            try {\n"
        "                pollHmiState();\n"
        "                pollContextPolicy();\n"
    )
    inject = (
        "            try {\n"
        "                if (com.luka.carplay.cluster.ClusterGeomOverride.poll())\n"
        "                    com.luka.carplay.cluster.ClusterLayerController.reapply();\n"
        "                pollHmiState();\n"
        "                pollContextPolicy();\n"
    )
    text = replace_once(text, anchor, inject, "ClusterStateController geometry poll")

    anchor = "            small = choiceValue == 1;\n"
    inject = (
        "            small = choiceValue == 1;\n"
        "            setViewAreaMode(small ? VIEWAREA_SMALLSCREEN : VIEWAREA_FULLSCREEN);\n"
    )
    text = replace_once(text, anchor, inject, "ClusterStateController view publish")

    anchor = "                if (ok) diag(\"ownership released -> ctx74\");\n"
    inject = (
        "                if (ok) {\n"
        "                    try { com.luka.carplay.cluster.ClusterLayerController.reapply(); }\n"
        "                    catch (Throwable t) { diag(\"WARN geometry restore failed: \" + describe(t)); }\n"
        "                    diag(\"ownership released -> ctx74\");\n"
        "                }\n"
    )
    text = replace_once(text, anchor, inject, "ClusterStateController release geometry")

    anchor = (
        "            diag(\"ownership acquired -> ctx80\");\n"
        "            return;\n"
    )
    inject = (
        "            try { com.luka.carplay.cluster.ClusterLayerController.reapply(); }\n"
        "            catch (Throwable t) { diag(\"WARN geometry apply after ctx80 failed: \" + describe(t)); }\n"
        "            diag(\"ownership acquired -> ctx80\");\n"
        "            return;\n"
    )
    text = replace_once(text, anchor, inject, "ClusterStateController acquire geometry")

    anchor = (
        "            if (!selectContext(CTX_COMPOSITE, \"reconcile\")) {\n"
        "                contextFailure(\"ctx80 reconcile failed\");\n"
        "            } else {\n"
        "                contextWriteFailures = 0;\n"
        "            }\n"
    )
    inject = (
        "            if (!selectContext(CTX_COMPOSITE, \"reconcile\")) {\n"
        "                contextFailure(\"ctx80 reconcile failed\");\n"
        "            } else {\n"
        "                contextWriteFailures = 0;\n"
        "                try { com.luka.carplay.cluster.ClusterLayerController.reapply(); }\n"
        "                catch (Throwable t) { diag(\"WARN geometry reapply after reconcile failed: \" + describe(t)); }\n"
        "            }\n"
    )
    text = replace_once(text, anchor, inject, "ClusterStateController reconcile geometry")
    return text


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--src-dir", required=True,
                   help="already-prepared unified Java source tree")
    p.add_argument("--luka-source", required=True,
                   help="pinned luka-dev/mib2q-carplay-rgi checkout")
    args = p.parse_args()

    luka_java = os.path.join(args.luka_source, "java_patch")
    luka_layers = os.path.join(
        luka_java, "com", "luka", "carplay", "cluster", "ClusterLayerController.java")
    luka_geom = os.path.join(
        luka_java, "com", "luka", "carplay", "cluster", "ClusterGeomOverride.java")
    luka_combi = os.path.join(
        luka_java, "de", "esolutions", "hmi", "widgets", "audi", "evo", "high",
        "widgets", "CombiMapController.java")
    controller = os.path.join(
        args.src_dir, "com", "luka", "carplay", "cluster", "ClusterStateController.java")

    required = (
        (controller, "prepared ClusterStateController"),
        (luka_layers, "Luka ClusterLayerController"),
        (luka_geom, "Luka ClusterGeomOverride"),
        (luka_combi, "Luka CombiMapController"),
    )
    for path, label in required:
        if not os.path.exists(path):
            fail("missing %s: %s" % (label, path))

    write_text(controller, patch_cluster_state_controller(controller))

    dst_cluster = os.path.join(args.src_dir, "com", "luka", "carplay", "cluster")
    write_text(os.path.join(dst_cluster, "ClusterLayerController.java"),
               patch_cluster_layer(luka_layers))
    shutil.copy2(luka_geom, os.path.join(dst_cluster, "ClusterGeomOverride.java"))

    dst_combi = os.path.join(
        args.src_dir, "de", "esolutions", "hmi", "widgets", "audi", "evo", "high",
        "widgets", "CombiMapController.java")
    write_text(dst_combi, patch_combi_map(luka_combi))

    print("Applied RGI geometry backport to: %s" % args.src_dir)
    print("  geometry: Luka Layout-derived planes 98/101/102")
    print("  ownership: existing JAVA80 / ClusterStateController")
    print("  lifecycle: unchanged (no V2.3 CarPlayScreenMonitor or auto lifecycle)")


if __name__ == "__main__":
    main()
