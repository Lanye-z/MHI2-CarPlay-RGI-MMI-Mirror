#ifndef MMI_CAPTURE_SOURCE_H
#define MMI_CAPTURE_SOURCE_H

#include "cluster_video_source.h"

struct MmiCaptureConfig {
    int width;
    int height;
    PixelFormat format;
    bool verbose;

    MmiCaptureConfig()
        : width(1024), height(480),
          format(PIXEL_FORMAT_BGRA8888), verbose(false) {
    }
};

class MmiCaptureSource : public ClusterVideoSource {
public:
    explicit MmiCaptureSource(const MmiCaptureConfig &cfg);
    virtual ~MmiCaptureSource();

    virtual bool init();
    virtual bool read_frame(VideoFrame *frame);
    virtual void shutdown();
    virtual const char *name() const { return "MHI2Q physical MMI display"; }

    bool is_ready() const { return ready_; }
    int stride() const { return stride_; }
    unsigned long frame_count() const { return frame_count_; }

private:
    MmiCaptureSource(const MmiCaptureSource &);
    MmiCaptureSource &operator=(const MmiCaptureSource &);

    bool open_screen();
    bool resolve_api();
    bool find_display();
    bool create_capture_buffer();
    static unsigned long long now_us();

    MmiCaptureConfig cfg_;
    bool ready_;
    int stride_;
    unsigned long frame_count_;

    void *screen_lib_;
    void *context_;
    void *display_;
    void *pixmap_;
    void *buffer_;
    unsigned char *pixels_;

    typedef int (*create_context_fn)(void **, int);
    typedef int (*destroy_context_fn)(void *);
    typedef int (*get_context_iv_fn)(void *, int, int *);
    typedef int (*get_context_pv_fn)(void *, int, void **);
    typedef int (*get_display_iv_fn)(void *, int, int *);
    typedef int (*create_pixmap_fn)(void **, void *);
    typedef int (*destroy_pixmap_fn)(void *);
    typedef int (*set_pixmap_iv_fn)(void *, int, const int *);
    typedef int (*create_pixmap_buffer_fn)(void *);
    typedef int (*get_pixmap_pv_fn)(void *, int, void **);
    typedef int (*get_buffer_pv_fn)(void *, int, void **);
    typedef int (*get_buffer_iv_fn)(void *, int, int *);
    typedef int (*read_display_fn)(void *, void *, int, const int *, int);

    create_context_fn create_context_;
    destroy_context_fn destroy_context_;
    get_context_iv_fn get_context_iv_;
    get_context_pv_fn get_context_pv_;
    get_display_iv_fn get_display_iv_;
    create_pixmap_fn create_pixmap_;
    destroy_pixmap_fn destroy_pixmap_;
    set_pixmap_iv_fn set_pixmap_iv_;
    create_pixmap_buffer_fn create_pixmap_buffer_;
    get_pixmap_pv_fn get_pixmap_pv_;
    get_buffer_pv_fn get_buffer_pv_;
    get_buffer_iv_fn get_buffer_iv_;
    read_display_fn read_display_;
};

#endif
