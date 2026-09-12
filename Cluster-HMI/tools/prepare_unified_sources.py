#!/usr/bin/env python3
"""Prepare the V2.2 unified carplay_hook.jar source tree.

Inputs:
  - pinned Lanye-z/mib2q-carplay-rgi-cn checkout (RGI/Amap business logic)
  - pinned luka-dev/mib2q-carplay-rgi checkout (MHI2Q DisplayManager ownership reference)

V2.2 keeps the user's RGI business logic, adopts Luka's already-proven MHI2Q
context-ownership seam, changes the composite to ctx80={98,101,102,3}, and
bridges renderer FRAME_READY/teardown into ClusterStateController.
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


def patch_display_manager(src):
    text = read_text(src)
    old = "this.dc[CTX_CARPLAY_NAV] = new DisplayContext(CTX_CARPLAY_NAV, new int[]{98, 101, 102, 33});"
    new = "this.dc[CTX_CARPLAY_NAV] = new DisplayContext(CTX_CARPLAY_NAV, new int[]{98, 101, 102, 3});"
    text = replace_once(text, old, new, "ctx80 composition")
    text = text.replace(
        "com.luka.carplay.core.ScreenModule.isConnected()",
        "com.luka.carplay.cluster.ClusterStateController.isClusterOwned()")
    text = text.replace(
        "com.luka.carplay.core.ScreenModule.isClusterContextWriterThread()",
        "com.luka.carplay.cluster.ClusterStateController.isContextWriterThread()")
    constructor_anchor = "        super(iframeworkaccess);\n"
    constructor_inject = (
        "        super(iframeworkaccess);\n"
        "        /* V2.2 shared Cluster/HMI control plane: Java owns terminal 1. */\n"
        "        com.luka.carplay.cluster.ClusterStateController.start(iframeworkaccess);\n"
    )
    text = replace_once(text, constructor_anchor, constructor_inject, "DisplayManager constructor")
    text = text.replace("dc[80] = {98, 101, 102, 33}", "dc[80] = {98, 101, 102, 3}")
    text = text.replace("planes 98/101/102/33", "planes 98/101/102/3")
    return text


def patch_carplay_hook(src):
    text = read_text(src)
    anchor = "        frameworkAccess = extractFramework(context);\n"
    inject = (
        "        frameworkAccess = extractFramework(context);\n"
        "        /* V2.2 Unified HMI controller is shared by BaseVideo and RGI. */\n"
        "        com.luka.carplay.cluster.ClusterStateController.start(frameworkAccess);\n"
        "        com.luka.carplay.cluster.ClusterStateController.setCarPlaySessionActive(true);\n"
    )
    text = replace_once(text, anchor, inject, "CarPlayHook activate")
    anchor = (
        "        active = false;\n"
        "        carplayRunning = false;\n"
        "        frameworkAccess = null;\n"
    )
    inject = (
        "        active = false;\n"
        "        carplayRunning = false;\n"
        "        com.luka.carplay.cluster.ClusterStateController.setCarPlaySessionActive(false);\n"
        "        com.luka.carplay.cluster.ClusterStateController.setRgiPresentationActive(false);\n"
        "        frameworkAccess = null;\n"
    )
    text = replace_once(text, anchor, inject, "CarPlayHook deactivate")
    anchor = "            carplayRunning = (carplay && activeState && selected);\n"
    inject = (
        "            carplayRunning = (carplay && activeState && selected);\n"
        "            com.luka.carplay.cluster.ClusterStateController.setCarPlaySessionActive(carplayRunning);\n"
    )
    text = replace_once(text, anchor, inject, "CarPlayHook device state")
    return text


def patch_renderer_server(src):
    text = read_text(src)
    anchor = (
        "            } else if (event == EVT_FRAME_READY) {\n"
        "                rendererReady = true;\n"
        "                frameReady = true;\n"
        "                lock.notifyAll();\n"
        "                Log.i(TAG, \"renderer frame ready\");\n"
        "            }\n"
    )
    inject = (
        "            } else if (event == EVT_FRAME_READY) {\n"
        "                rendererReady = true;\n"
        "                frameReady = true;\n"
        "                com.luka.carplay.cluster.ClusterStateController.setRgiPresentationActive(true);\n"
        "                lock.notifyAll();\n"
        "                Log.i(TAG, \"renderer frame ready\");\n"
        "            }\n"
    )
    text = replace_once(text, anchor, inject, "RendererServer FRAME_READY")
    anchor = (
        "    public boolean sendHideDisplay() {\n"
        "        byte[] pkt = new byte[PKT_SIZE];\n"
        "        pkt[0] = CMD_HIDE_DISPLAY;\n"
        "        return sendPacket(pkt);\n"
        "    }\n"
    )
    inject = (
        "    public boolean sendHideDisplay() {\n"
        "        com.luka.carplay.cluster.ClusterStateController.setRgiPresentationActive(false);\n"
        "        byte[] pkt = new byte[PKT_SIZE];\n"
        "        pkt[0] = CMD_HIDE_DISPLAY;\n"
        "        return sendPacket(pkt);\n"
        "    }\n"
    )
    text = replace_once(text, anchor, inject, "RendererServer hide")
    anchor = (
        "        rendererReady = false;\n"
        "        frameReady = false;\n"
        "        lock.notifyAll();\n"
    )
    inject = (
        "        rendererReady = false;\n"
        "        frameReady = false;\n"
        "        com.luka.carplay.cluster.ClusterStateController.setRgiPresentationActive(false);\n"
        "        lock.notifyAll();\n"
    )
    text = replace_once(text, anchor, inject, "RendererServer close")
    return text


def patch_bap_bridge(src):
    """Detach the RGI renderer lifecycle from legacy ClusterService ctx74 routing."""
    text = read_text(src)

    import_anchor = "import com.luka.carplay.CarPlayHook;\n"
    import_inject = (
        "import com.luka.carplay.CarPlayHook;\n"
        "import com.luka.carplay.cluster.ClusterStateController;\n"
    )
    text = replace_once(text, import_anchor, import_inject, "BAPBridge controller import")

    activation_old = (
        "        String result = csRef.activateCustomRendererPipeline();\n"
        "        Log.i(TAG, \"CR: real-maneuver pipeline \" + result);\n"
        "        if (result == null || result.startsWith(\"FAILED\")) {\n"
        "            abortPreparedCustomRenderer(\"pipeline activation failed\");\n"
        "            return false;\n"
        "        }\n"
    )
    activation_new = (
        "        /* JAVA80: RendererServer FRAME_READY has already raised\n"
        "         * rgiPresentationActive. ClusterStateController owns the\n"
        "         * 72->80 transition/reconciliation; do not call the legacy\n"
        "         * ClusterService displayable20/ctx74 pipeline here. */\n"
        "        Log.i(TAG, \"CR: real-maneuver pipeline JAVA80 delegated to ClusterStateController\");\n"
    )
    text = replace_once(text, activation_old, activation_new, "BAPBridge JAVA80 activation")

    one_line_old = "if (csRef != null) csRef.deactivateCustomRendererPipeline();"
    one_line_count = text.count(one_line_old)
    if one_line_count < 1:
        fail("BAPBridge legacy one-line teardown calls not found")
    text = text.replace(one_line_old, "ClusterStateController.setRgiPresentationActive(false);")

    block_old = (
        "            if (csRef != null) {\n"
        "                csRef.deactivateCustomRendererPipeline();\n"
        "            }\n"
    )
    block_new = "            ClusterStateController.setRgiPresentationActive(false);\n"
    if block_old in text:
        text = text.replace(block_old, block_new)

    if "activateCustomRendererPipeline()" in text or "deactivateCustomRendererPipeline()" in text:
        fail("BAPBridge still contains legacy ClusterService custom-renderer pipeline calls")
    return text


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--rgi-source", required=True)
    p.add_argument("--luka-source", required=True)
    p.add_argument("--output-src", required=True)
    p.add_argument("--controller-source", required=True)
    args = p.parse_args()

    rgi_java = os.path.join(args.rgi_source, "java_patch")
    luka_dm = os.path.join(args.luka_source, "java_patch", "de", "audi", "tghu", "fwhmi", "DisplayManagerMIB2High.java")
    controller = args.controller_source
    for path, label in ((rgi_java, "RGI java_patch"), (luka_dm, "Luka DisplayManagerMIB2High"),
                        (controller, "ClusterStateController")):
        if not os.path.exists(path):
            fail("missing %s: %s" % (label, path))

    if os.path.isdir(args.output_src):
        shutil.rmtree(args.output_src)
    shutil.copytree(rgi_java, args.output_src)

    dst_controller = os.path.join(args.output_src, "com", "luka", "carplay", "cluster", "ClusterStateController.java")
    os.makedirs(os.path.dirname(dst_controller), exist_ok=True)
    shutil.copy2(controller, dst_controller)

    hook = os.path.join(args.output_src, "com", "luka", "carplay", "CarPlayHook.java")
    write_text(hook, patch_carplay_hook(hook))

    renderer_server = os.path.join(args.output_src, "com", "luka", "carplay", "routeguidance", "RendererServer.java")
    if not os.path.exists(renderer_server):
        fail("missing user's RendererServer: %s" % renderer_server)
    write_text(renderer_server, patch_renderer_server(renderer_server))

    bap_bridge = os.path.join(args.output_src, "com", "luka", "carplay", "routeguidance", "BAPBridge.java")
    if not os.path.exists(bap_bridge):
        fail("missing user's BAPBridge: %s" % bap_bridge)
    write_text(bap_bridge, patch_bap_bridge(bap_bridge))

    dst_dm = os.path.join(args.output_src, "de", "audi", "tghu", "fwhmi", "DisplayManagerMIB2High.java")
    write_text(dst_dm, patch_display_manager(luka_dm))

    print("Prepared V2.2 unified Java source tree: %s" % args.output_src)
    print("  RGI source:      %s" % args.rgi_source)
    print("  Luka HMI source: %s" % args.luka_source)
    print("  ctx80 contract:  {98,101,102,3}")
    print("  ownership:       JAVA80 / single Java context writer")
    print("  RGI seam:        FRAME_READY -> rgiPresentationActive; BAPBridge has no legacy ctx74 pipeline calls")


if __name__ == "__main__":
    main()
