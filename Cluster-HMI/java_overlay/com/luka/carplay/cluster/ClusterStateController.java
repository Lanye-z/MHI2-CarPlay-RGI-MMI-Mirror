/*
 * Unified Cluster HMI control plane for Lanye-z/test V2.2.
 *
 * Final V2.2 contract:
 *   - Java/HMI is the single Cluster context owner;
 *   - native renderers own pixels only (displayable 3 / 98);
 *   - ctx80={98,101,102,3};
 *   - Luka-style DisplayManager guard blocks non-owner physical context writes;
 *   - observer/ownership diagnostics are persisted under /tmp for vehicle tests.
 *
 * Java 1.2 source level: no generics, enums or newer language features.
 */
package com.luka.carplay.cluster;

import com.luka.carplay.framework.Log;

import de.audi.atip.base.IFrameworkAccess;
import de.audi.atip.hmi.HMIService;
import de.audi.atip.hmi.model.HMIModel;
import de.audi.atip.hmi.modelaccess.ChoiceModelGUI;
import de.audi.atip.hmi.view.IDisplayManager;
import de.audi.atip.model.ICoreNaviModelBank;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.reflect.Method;

public final class ClusterStateController {
    private static final String TAG = "ClusterState";

    public static final int TERMINAL_CLUSTER = 1;
    public static final int CTX_STOCK = 74;
    public static final int CTX_BOUNCE = 72;
    public static final int CTX_COMPOSITE = 80;

    private static final long POLL_MS = 100L;
    private static final long RECONCILE_MS = 250L;
    private static final long BOUNCE_MS = 180L;
    private static final long CIRCUIT_BREAKER_MS = 2000L;
    private static final int CONTEXT_FAILURE_LIMIT = 3;
    private static final long DIAG_MAX_BYTES = 131072L;

    private static final String HMI_STATE_FILE = "/tmp/mmi-mirror-hmi.state";
    private static final String BASEVIDEO_ACTIVE_FILE = "/tmp/mmi-mirror-active";
    private static final String BASEVIDEO_READY_FILE = "/tmp/mmi-mirror-basevideo.ready";
    private static final String STARTED_FILE = "/tmp/mmi-mirror-controller.started";
    private static final String DIAG_FILE = "/tmp/mmi-mirror-controller.log";

    private static final Object LOCK = new Object();
    private static final Object DIAG_LOCK = new Object();
    private static volatile IFrameworkAccess frameworkAccess;
    private static volatile Thread worker;
    private static volatile Thread contextWriterThread;

    /* Published before a physical context write, matching Luka's ownership rule. */
    private static volatile boolean ownershipIntent;
    private static volatile boolean compositeApplied;
    private static volatile boolean carPlaySessionActive;
    private static volatile boolean rgiPresentationActive;

    private static String lastStateSignature = "";
    private static String lastObserverStatus = "";
    private static long lastReconcileMs;
    private static int contextWriteFailures;
    private static long circuitOpenUntilMs;

    private ClusterStateController() {}

    /** Called from DisplayManagerMIB2High constructor and CarPlayHook. Idempotent. */
    public static void start(IFrameworkAccess fw) {
        if (fw != null) frameworkAccess = fw;
        synchronized (LOCK) {
            if (worker != null && worker.isAlive()) {
                LOCK.notifyAll();
                return;
            }
            try {
                writeStartedMarker();
                diag("controller start requested; frameworkAccess=" + (frameworkAccess != null ? "ok" : "null"));
                Thread t = new Thread(new Runnable() {
                    public void run() { runLoop(); }
                }, "cluster-state-controller");
                t.setDaemon(true);
                t.start();
                worker = t;
                Log.i(TAG, "V2.2 controller started; Java is the sole Cluster context owner");
            } catch (Throwable t) {
                diag("ERROR worker start failed: " + describe(t));
                Log.e(TAG, "worker start failed", t);
            }
        }
    }

    public static void setCarPlaySessionActive(boolean active) {
        if (carPlaySessionActive == active) return;
        carPlaySessionActive = active;
        lastStateSignature = "";
        diag("carplay_session=" + (active ? "1" : "0"));
    }

    /** Renderer presentation seam: true only after an RGI frame is ready. */
    public static void setRgiPresentationActive(boolean active) {
        if (rgiPresentationActive == active) return;
        rgiPresentationActive = active;
        lastStateSignature = "";
        diag("rgi_active=" + (active ? "1" : "0"));
    }

    public static boolean isRgiPresentationActive() {
        return rgiPresentationActive;
    }

    /** DisplayManager guard uses intent, not the last observed/applied context. */
    public static boolean isClusterOwned() {
        return ownershipIntent;
    }

    public static boolean isContextWriterThread() {
        return Thread.currentThread() == contextWriterThread;
    }

    private static void runLoop() {
        contextWriterThread = Thread.currentThread();
        diag("worker running; writerThread=" + contextWriterThread.getName());
        while (true) {
            try {
                pollHmiState();
                pollContextPolicy();
            } catch (Throwable t) {
                diag("ERROR poll failed: " + describe(t));
                Log.w(TAG, "poll failed: " + t);
            }
            sleep(POLL_MS);
        }
    }

    /* ============================================================
     * Layout / View observer
     * ============================================================ */

    private static void pollHmiState() {
        IFrameworkAccess fw = frameworkAccess;
        if (fw == null) {
            observerStatus("frameworkAccess=null");
            return;
        }

        HMIService hmi;
        try {
            hmi = fw.getHMIService();
        } catch (Throwable t) {
            observerStatus("getHMIService failed: " + describe(t));
            return;
        }
        if (hmi == null) {
            observerStatus("HMIService=null");
            return;
        }

        boolean small;
        String choiceClass;
        int choiceValue;
        try {
            HMIModel model = hmi.getModel(ICoreNaviModelBank.NAV_VIEW_SIZE_CHOICE);
            if (model == null) {
                observerStatus("NAV_VIEW_SIZE_CHOICE model=null");
                return;
            }
            choiceClass = model.getClass().getName();
            if (!(model instanceof ChoiceModelGUI)) {
                observerStatus("NAV_VIEW_SIZE_CHOICE unexpected class=" + choiceClass);
                return;
            }
            choiceValue = ((ChoiceModelGUI) model).getValue();
            small = choiceValue == 1;
        } catch (Throwable t) {
            observerStatus("NAV_VIEW_SIZE_CHOICE read failed: " + describe(t));
            return;
        }

        String layoutName = "unknown";
        int smallDx = 0;
        int smallDy = 0;
        try {
            Object terminal = hmi.getHMITerminal(TERMINAL_CLUSTER);
            if (terminal == null) {
                observerStatus("getHMITerminal(1)=null; choice=" + choiceValue + " class=" + choiceClass);
                return;
            }
            Method getLayout = terminal.getClass().getMethod("getLayout", new Class[0]);
            Object layout = getLayout.invoke(terminal, new Object[0]);
            if (layout == null) {
                observerStatus("terminal1 layout=null; choice=" + choiceValue + " class=" + choiceClass);
                return;
            }
            layoutName = layout.getClass().getName();
            Method getInt = layout.getClass().getMethod(
                "getIntegerConstant", new Class[]{Integer.TYPE});
            smallDx = ((Integer)getInt.invoke(layout, new Object[]{new Integer(80)})).intValue();
            smallDy = ((Integer)getInt.invoke(layout, new Object[]{new Integer(81)})).intValue();
        } catch (Throwable t) {
            observerStatus("terminal/layout read failed: " + describe(t)
                + " choice=" + choiceValue + " class=" + choiceClass);
            return;
        }

        String lower = layoutName.toLowerCase();
        boolean sport = lower.indexOf("sport") >= 0 || smallDx != 0 || smallDy != 0;
        String layout = sport ? "SPORT" : "CLASSIC";
        String view = small ? "SMALL" : "FULL";
        observerStatus("ok choice=" + choiceValue + " choiceClass=" + choiceClass
            + " layoutClass=" + layoutName + " c80=" + smallDx + " c81=" + smallDy
            + " -> " + layout + "_" + view);

        String signature = layout + "/" + view + "/" + layoutName + "/" + smallDx + "/" + smallDy
            + "/cp=" + (carPlaySessionActive ? "1" : "0")
            + "/rgi=" + (rgiPresentationActive ? "1" : "0");

        if (!signature.equals(lastStateSignature)) {
            lastStateSignature = signature;
            if (writeHmiState(layout, view, layoutName, smallDx, smallDy)) {
                diag("state published: " + layout + "_" + view + " layoutClass=" + layoutName
                    + " c80=" + smallDx + " c81=" + smallDy);
            }
            Log.i(TAG, "layout=" + layout + " view=" + view
                + " source=" + layoutName + " smallOffset=(" + smallDx + "," + smallDy + ")");
        }
    }

    private static boolean writeHmiState(String layout, String view, String layoutName,
                                         int smallDx, int smallDy) {
        File tmp = new File(HMI_STATE_FILE + ".tmp");
        File dst = new File(HMI_STATE_FILE);
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(tmp);
            String text = "layout=" + layout + "\n"
                + "view=" + view + "\n"
                + "layout_name=" + layoutName + "\n"
                + "small_stage_dx=" + smallDx + "\n"
                + "small_stage_dy=" + smallDy + "\n"
                + "carplay_session=" + (carPlaySessionActive ? "1" : "0") + "\n"
                + "rgi_active=" + (rgiPresentationActive ? "1" : "0") + "\n";
            out.write(text.getBytes("UTF-8"));
            out.flush();
            out.close();
            out = null;
            if (dst.exists() && !dst.delete()) {
                diag("WARN could not delete old state file before replace");
            }
            if (!tmp.renameTo(dst)) {
                copyFile(tmp, dst);
                tmp.delete();
            }
            return true;
        } catch (Throwable t) {
            diag("ERROR state write failed: " + describe(t));
            Log.w(TAG, "state write failed: " + t);
            try { if (out != null) out.close(); } catch (Throwable ignored) {}
            return false;
        }
    }

    private static void observerStatus(String status) {
        if (status.equals(lastObserverStatus)) return;
        lastObserverStatus = status;
        diag("observer: " + status);
    }

    /* ============================================================
     * Final V2.2 context controller
     * ============================================================ */

    private static void pollContextPolicy() {
        boolean baseActive = new File(BASEVIDEO_ACTIVE_FILE).exists();
        boolean baseReady = new File(BASEVIDEO_READY_FILE).exists();
        boolean wantComposite = (baseActive && baseReady) || rgiPresentationActive;

        if (!wantComposite) {
            if (ownershipIntent || compositeApplied) {
                ownershipIntent = false; /* release guard before stock switch */
                boolean ok = selectContext(CTX_STOCK, "release");
                compositeApplied = false;
                contextWriteFailures = 0;
                if (ok) diag("ownership released -> ctx74");
            }
            return;
        }

        long now = nowMs();
        if (now < circuitOpenUntilMs) return;

        ownershipIntent = true; /* close race before the first switch */
        IDisplayManager dm = displayManager();
        if (dm == null) {
            contextFailure("DisplayManager unavailable");
            return;
        }

        if (!compositeApplied) {
            int actual = currentContext(dm);
            diag("ownership acquire requested; base=" + (baseActive ? "1" : "0")
                + "/" + (baseReady ? "1" : "0") + " rgi=" + (rgiPresentationActive ? "1" : "0")
                + " actual=" + actual);
            if (actual != CTX_COMPOSITE) {
                if (!selectContext(CTX_BOUNCE, "enter-bounce")) {
                    contextFailure("ctx72 bounce failed");
                    return;
                }
                sleep(BOUNCE_MS);
                if (!ownershipIntent) return;
                if (!selectContext(CTX_COMPOSITE, "enter-composite")) {
                    contextFailure("ctx80 enter failed");
                    return;
                }
            }
            compositeApplied = true;
            contextWriteFailures = 0;
            lastReconcileMs = nowMs();
            diag("ownership acquired -> ctx80");
            return;
        }

        /* Low-cost Java/HMI safety check only. No shell/native context watchdog exists. */
        now = nowMs();
        if (now - lastReconcileMs < RECONCILE_MS) return;
        lastReconcileMs = now;
        int actual = currentContext(dm);
        if (actual >= 0 && actual != CTX_COMPOSITE) {
            diag("physical context drift actual=" + actual + " desired=80 -> Java reconcile");
            if (!selectContext(CTX_COMPOSITE, "reconcile")) {
                contextFailure("ctx80 reconcile failed");
            } else {
                contextWriteFailures = 0;
            }
        }
    }

    private static IDisplayManager displayManager() {
        try {
            IFrameworkAccess fw = frameworkAccess;
            if (fw == null || fw.getHMIService() == null) return null;
            return fw.getHMIService().getDisplayManager();
        } catch (Throwable t) {
            diag("DisplayManager lookup failed: " + describe(t));
            return null;
        }
    }

    private static int currentContext(IDisplayManager dm) {
        try { return dm.getCurrentContextID(TERMINAL_CLUSTER); }
        catch (Throwable t) {
            diag("currentContext read failed: " + describe(t));
            return -1;
        }
    }

    private static boolean selectContext(int context, String reason) {
        IDisplayManager dm = displayManager();
        if (dm == null) return false;
        try {
            diag(reason + " -> ctx" + context);
            Log.i(TAG, reason + " -> ctx " + context);
            dm.switchContext(context, TERMINAL_CLUSTER, null);
            return true;
        } catch (Throwable t) {
            diag("ERROR switch ctx" + context + " failed: " + describe(t));
            Log.w(TAG, "switch ctx " + context + " failed: " + t);
            return false;
        }
    }

    private static void contextFailure(String reason) {
        ++contextWriteFailures;
        diag("context failure " + contextWriteFailures + "/" + CONTEXT_FAILURE_LIMIT + ": " + reason);
        if (contextWriteFailures < CONTEXT_FAILURE_LIMIT) return;
        ownershipIntent = false;
        compositeApplied = false;
        circuitOpenUntilMs = nowMs() + CIRCUIT_BREAKER_MS;
        contextWriteFailures = 0;
        diag("context circuit breaker OPEN for " + CIRCUIT_BREAKER_MS + " ms; ownership released");
    }

    /* ============================================================
     * Diagnostics
     * ============================================================ */

    private static void writeStartedMarker() {
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(STARTED_FILE);
            String text = "started=1\ntime_ms=" + nowMs() + "\nowner=JAVA\nctx=80\n";
            out.write(text.getBytes("UTF-8"));
            out.close();
        } catch (Throwable t) {
            try { if (out != null) out.close(); } catch (Throwable ignored) {}
        }
    }

    private static void diag(String text) {
        synchronized (DIAG_LOCK) {
            FileOutputStream out = null;
            try {
                File f = new File(DIAG_FILE);
                if (f.exists() && f.length() > DIAG_MAX_BYTES) {
                    FileOutputStream reset = new FileOutputStream(f, false);
                    reset.write(("--- log reset at " + nowMs() + " ---\n").getBytes("UTF-8"));
                    reset.close();
                }
                out = new FileOutputStream(f, true);
                String line = nowMs() + " " + text + "\n";
                out.write(line.getBytes("UTF-8"));
                out.close();
            } catch (Throwable ignored) {
                try { if (out != null) out.close(); } catch (Throwable ignored2) {}
            }
        }
    }

    private static String describe(Throwable t) {
        if (t == null) return "unknown";
        String m = t.getMessage();
        return t.getClass().getName() + (m == null ? "" : ": " + m);
    }

    private static void copyFile(File src, File dst) throws Exception {
        FileInputStream in = new FileInputStream(src);
        FileOutputStream out = new FileOutputStream(dst);
        byte[] buf = new byte[512];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        in.close(); out.close();
    }

    private static long nowMs() { return System.currentTimeMillis(); }

    private static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }
}
