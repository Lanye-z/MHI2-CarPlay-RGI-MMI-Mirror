#include "mhi2q_backend.h"

#include <GLES2/gl2.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SCR_PROP_VISIBLE         51
#define SCR_PROP_MANAGER_STRING 152

static const char *kManagedGroup = "All your base are belong to us!";

Mhi2qBackend::Mhi2qBackend()
    : ready_(false),
      display_lib_(0),
      screen_lib_(0),
      display_init_(0),
      display_create_window_(0),
      screen_destroy_window_(0),
      screen_get_window_property_iv_(0),
      screen_get_window_property_cv_(0),
      egl_display_(EGL_NO_DISPLAY),
      egl_config_(0),
      egl_surface_(EGL_NO_SURFACE),
      egl_context_(EGL_NO_CONTEXT),
      native_window_(0),
      kd_window_(0) {
    memset(&cfg_, 0, sizeof(cfg_));
}

Mhi2qBackend::~Mhi2qBackend() {
    shutdown();
}

bool Mhi2qBackend::open_displayinit() {
    static const char *paths[] = {
        "/mnt/app/eso/lib/libdisplayinit.so",
        "/eso/lib/libdisplayinit.so",
        "/mnt/app/armle/lib/libdisplayinit.so",
        "/lib/libdisplayinit.so",
        "/usr/lib/libdisplayinit.so",
        "libdisplayinit.so",
        0
    };

    for (int i = 0; paths[i]; ++i) {
        display_lib_ = dlopen(paths[i], RTLD_LAZY);
        if (display_lib_) {
            fprintf(stderr, "backend: loaded %s\n", paths[i]);
            break;
        }
    }
    if (!display_lib_) {
        fprintf(stderr, "backend: failed to load libdisplayinit.so: %s\n", dlerror());
        return false;
    }

    display_init_ = (display_init_fn)dlsym(display_lib_, "display_init");
    display_create_window_ =
        (display_create_window_fn)dlsym(display_lib_, "display_create_window");

    if (!display_init_ || !display_create_window_) {
        fprintf(stderr,
                "backend: missing display_init/display_create_window: %s\n",
                dlerror());
        return false;
    }
    return true;
}

bool Mhi2qBackend::open_screen_api() {
    screen_lib_ = dlopen("libscreen.so.1", RTLD_LAZY);
    if (!screen_lib_) screen_lib_ = dlopen("libscreen.so", RTLD_LAZY);
    if (!screen_lib_) {
        fprintf(stderr,
                "backend: WARN libscreen unavailable; ownership diagnostics disabled\n");
        return true;
    }

    screen_destroy_window_ =
        (screen_destroy_window_fn)dlsym(screen_lib_, "screen_destroy_window");
    screen_get_window_property_iv_ =
        (screen_get_property_iv_fn)dlsym(screen_lib_, "screen_get_window_property_iv");
    screen_get_window_property_cv_ =
        (screen_get_property_cv_fn)dlsym(screen_lib_, "screen_get_window_property_cv");

    if (cfg_.verbose) {
        fprintf(stderr,
                "backend: libscreen destroy=%p get_iv=%p get_cv=%p\n",
                (void *)screen_destroy_window_,
                (void *)screen_get_window_property_iv_,
                (void *)screen_get_window_property_cv_);
    }
    return true;
}

void Mhi2qBackend::log_egl_error(const char *where) {
    fprintf(stderr, "backend: %s EGL error=0x%04x\n", where, (unsigned)eglGetError());
}

bool Mhi2qBackend::init_egl() {
    egl_display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (egl_display_ == EGL_NO_DISPLAY) {
        log_egl_error("eglGetDisplay");
        return false;
    }
    EGLint major = 0, minor = 0;
    if (!eglInitialize(egl_display_, &major, &minor)) {
        log_egl_error("eglInitialize");
        return false;
    }
    fprintf(stderr, "backend: EGL initialized %d.%d\n", (int)major, (int)minor);

    const EGLint attrs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };

    EGLint count = 0;
    if (!eglChooseConfig(egl_display_, attrs, &egl_config_, 1, &count) || count < 1) {
        log_egl_error("eglChooseConfig RGBA8888");
        return false;
    }
    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        log_egl_error("eglBindAPI");
        return false;
    }
    const EGLint ctx_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    egl_context_ = eglCreateContext(egl_display_, egl_config_, EGL_NO_CONTEXT, ctx_attrs);
    if (egl_context_ == EGL_NO_CONTEXT) {
        log_egl_error("eglCreateContext");
        return false;
    }
    return true;
}

bool Mhi2qBackend::create_native_window() {
    native_window_ = 0;
    kd_window_ = 0;

    const int ret = display_create_window_(egl_display_, egl_config_,
                                            cfg_.width, cfg_.height,
                                            cfg_.displayable_id,
                                            &native_window_, &kd_window_);
    fprintf(stderr,
            "backend: display_create_window ret=%d displayable=%d size=%dx%d native=%p kd=%d\n",
            ret, cfg_.displayable_id, cfg_.width, cfg_.height,
            (void *)(uintptr_t)native_window_, kd_window_);

    if (!native_window_) {
        fprintf(stderr, "backend: display_create_window FAILED (native window is null)\n");
        return false;
    }

    egl_surface_ = eglCreateWindowSurface(egl_display_, egl_config_, native_window_, 0);
    if (egl_surface_ == EGL_NO_SURFACE) {
        log_egl_error("eglCreateWindowSurface");
        return false;
    }
    if (!eglMakeCurrent(egl_display_, egl_surface_, egl_surface_, egl_context_)) {
        log_egl_error("eglMakeCurrent");
        return false;
    }
    fprintf(stderr, "backend: eglMakeCurrent OK\n");
    return true;
}

void Mhi2qBackend::probe_managed_window() {
    if (!native_window_) return;
    usleep(150000);

    if (screen_get_window_property_iv_) {
        int visible = -1;
        errno = 0;
        const int rc = screen_get_window_property_iv_(
            (void *)(uintptr_t)native_window_, SCR_PROP_VISIBLE, &visible);
        fprintf(stderr,
                "backend: window visible probe rc=%d visible=%d errno=%d\n",
                rc, visible, errno);
    }

    if (screen_get_window_property_cv_) {
        char manager[96];
        memset(manager, 0, sizeof(manager));
        errno = 0;
        const int rc = screen_get_window_property_cv_(
            (void *)(uintptr_t)native_window_,
            SCR_PROP_MANAGER_STRING,
            (int)sizeof(manager) - 1,
            manager);
        fprintf(stderr,
                "backend: manager-string rc=%d value='%s' errno=%d%s\n",
                rc, manager, errno,
                (rc == 0 && strcmp(manager, kManagedGroup) == 0)
                    ? " [managed by displaymanager]" : "");
    }
}

bool Mhi2qBackend::init(const Mhi2qBackendConfig &cfg) {
    cfg_ = cfg;
    if (!getenv("IPL_CONFIG_DIR"))
        setenv("IPL_CONFIG_DIR", "/etc/eso/production", 0);

    fprintf(stderr,
            "backend: init size=%dx%d displayable=%d context_owner=java\n",
            cfg_.width, cfg_.height, cfg_.displayable_id);

    if (!open_displayinit()) return false;
    display_init_(0, 0);
    fprintf(stderr, "backend: display_init complete (library handle kept open)\n");

    open_screen_api();
    if (!init_egl()) {
        shutdown();
        return false;
    }
    if (!create_native_window()) {
        shutdown();
        return false;
    }

    probe_managed_window();
    ready_ = true;
    return true;
}

void Mhi2qBackend::swap() {
    if (!ready_ || egl_surface_ == EGL_NO_SURFACE) return;
    if (!eglSwapBuffers(egl_display_, egl_surface_))
        log_egl_error("eglSwapBuffers");
}

void Mhi2qBackend::destroy_native_window() {
    if (egl_display_ != EGL_NO_DISPLAY) {
        eglMakeCurrent(egl_display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (egl_surface_ != EGL_NO_SURFACE) {
            eglDestroySurface(egl_display_, egl_surface_);
            egl_surface_ = EGL_NO_SURFACE;
        }
    }

    if (native_window_ && screen_destroy_window_) {
        errno = 0;
        const int rc = screen_destroy_window_((void *)(uintptr_t)native_window_);
        fprintf(stderr, "backend: screen_destroy_window rc=%d errno=%d\n", rc, errno);
    }
    native_window_ = 0;

    if (egl_display_ != EGL_NO_DISPLAY && egl_context_ != EGL_NO_CONTEXT) {
        eglDestroyContext(egl_display_, egl_context_);
        egl_context_ = EGL_NO_CONTEXT;
    }
    if (egl_display_ != EGL_NO_DISPLAY) {
        eglTerminate(egl_display_);
        egl_display_ = EGL_NO_DISPLAY;
    }
}

void Mhi2qBackend::shutdown() {
    if (!display_lib_ && egl_display_ == EGL_NO_DISPLAY && !native_window_)
        return;

    destroy_native_window();

    if (screen_lib_) {
        dlclose(screen_lib_);
        screen_lib_ = 0;
    }
    if (display_lib_) {
        dlclose(display_lib_);
        display_lib_ = 0;
    }
    display_init_ = 0;
    display_create_window_ = 0;
    screen_destroy_window_ = 0;
    screen_get_window_property_iv_ = 0;
    screen_get_window_property_cv_ = 0;
    ready_ = false;
}
