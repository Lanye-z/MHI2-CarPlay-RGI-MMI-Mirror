#ifndef MHI2Q_BACKEND_H
#define MHI2Q_BACKEND_H

#include <EGL/egl.h>

struct Mhi2qBackendConfig {
    int width;
    int height;
    int displayable_id;
    bool verbose;
};

class Mhi2qBackend {
public:
    Mhi2qBackend();
    ~Mhi2qBackend();

    /* Create the managed displayable window and EGL surface only.
     * Native never reads or writes Cluster context. */
    bool init(const Mhi2qBackendConfig &cfg);
    void swap();
    void shutdown();

    int width() const { return cfg_.width; }
    int height() const { return cfg_.height; }
    bool is_ready() const { return ready_; }

private:
    Mhi2qBackend(const Mhi2qBackend &);
    Mhi2qBackend &operator=(const Mhi2qBackend &);

    bool open_displayinit();
    bool init_egl();
    bool create_native_window();
    bool open_screen_api();
    void probe_managed_window();
    void destroy_native_window();
    void log_egl_error(const char *where);

    Mhi2qBackendConfig cfg_;
    bool ready_;

    void *display_lib_;
    void *screen_lib_;

    typedef void (*display_init_fn)(int, int);
    typedef int (*display_create_window_fn)(EGLDisplay, EGLConfig, int, int, int,
                                            EGLNativeWindowType *, int *);
    display_init_fn display_init_;
    display_create_window_fn display_create_window_;

    typedef int (*screen_destroy_window_fn)(void *);
    typedef int (*screen_get_property_iv_fn)(void *, int, int *);
    typedef int (*screen_get_property_cv_fn)(void *, int, int, char *);
    screen_destroy_window_fn screen_destroy_window_;
    screen_get_property_iv_fn screen_get_window_property_iv_;
    screen_get_property_cv_fn screen_get_window_property_cv_;

    EGLDisplay egl_display_;
    EGLConfig egl_config_;
    EGLSurface egl_surface_;
    EGLContext egl_context_;
    EGLNativeWindowType native_window_;
    int kd_window_;
};

#endif
