#include "mmi_capture_source.h"

#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>

/* QNX Screen values verified on MHI2Q/P1404 by the public MMI mirror research. */
#define SCREEN_PROPERTY_BUFFER_SIZE 5
#define SCREEN_PROPERTY_FORMAT 14
#define SCREEN_PROPERTY_POINTER 34
#define SCREEN_PROPERTY_RENDER_BUFFERS 37
#define SCREEN_PROPERTY_SIZE 40
#define SCREEN_PROPERTY_STRIDE 44
#define SCREEN_PROPERTY_USAGE 48
#define SCREEN_PROPERTY_DISPLAY_COUNT 59
#define SCREEN_PROPERTY_DISPLAYS 60

#define SCREEN_FORMAT_RGBA8888 8
#define SCREEN_USAGE_READ (1 << 1)
#define SCREEN_USAGE_NATIVE (1 << 3)
#define SCREEN_DISPLAY_MANAGER_CONTEXT (1 << 3)
#define SCREEN_WINDOW_MANAGER_CONTEXT (1 << 0)

MmiCaptureSource::MmiCaptureSource(const MmiCaptureConfig &cfg)
    : cfg_(cfg), ready_(false), stride_(0), frame_count_(0),
      screen_lib_(0), context_(0), display_(0), pixmap_(0), buffer_(0), pixels_(0),
      create_context_(0), destroy_context_(0), get_context_iv_(0), get_context_pv_(0),
      get_display_iv_(0), create_pixmap_(0), destroy_pixmap_(0), set_pixmap_iv_(0),
      create_pixmap_buffer_(0), get_pixmap_pv_(0), get_buffer_pv_(0),
      get_buffer_iv_(0), read_display_(0) {
}

MmiCaptureSource::~MmiCaptureSource() {
    shutdown();
}

unsigned long long MmiCaptureSource::now_us() {
    struct timeval tv;
    if (gettimeofday(&tv, 0) != 0) return 0;
    return (unsigned long long)(unsigned long)tv.tv_sec * 1000000ULL +
           (unsigned long long)(unsigned long)tv.tv_usec;
}

bool MmiCaptureSource::open_screen() {
    screen_lib_ = dlopen("libscreen.so.1", RTLD_LAZY);
    if (!screen_lib_)
        screen_lib_ = dlopen("libscreen.so", RTLD_LAZY);
    if (!screen_lib_) {
        fprintf(stderr, "capture: unable to load libscreen.so.1/libscreen.so\n");
        return false;
    }
    return true;
}

bool MmiCaptureSource::resolve_api() {
    create_context_ = (create_context_fn)dlsym(screen_lib_, "screen_create_context");
    destroy_context_ = (destroy_context_fn)dlsym(screen_lib_, "screen_destroy_context");
    get_context_iv_ = (get_context_iv_fn)dlsym(screen_lib_, "screen_get_context_property_iv");
    get_context_pv_ = (get_context_pv_fn)dlsym(screen_lib_, "screen_get_context_property_pv");
    get_display_iv_ = (get_display_iv_fn)dlsym(screen_lib_, "screen_get_display_property_iv");
    create_pixmap_ = (create_pixmap_fn)dlsym(screen_lib_, "screen_create_pixmap");
    destroy_pixmap_ = (destroy_pixmap_fn)dlsym(screen_lib_, "screen_destroy_pixmap");
    set_pixmap_iv_ = (set_pixmap_iv_fn)dlsym(screen_lib_, "screen_set_pixmap_property_iv");
    create_pixmap_buffer_ = (create_pixmap_buffer_fn)dlsym(screen_lib_, "screen_create_pixmap_buffer");
    get_pixmap_pv_ = (get_pixmap_pv_fn)dlsym(screen_lib_, "screen_get_pixmap_property_pv");
    get_buffer_pv_ = (get_buffer_pv_fn)dlsym(screen_lib_, "screen_get_buffer_property_pv");
    get_buffer_iv_ = (get_buffer_iv_fn)dlsym(screen_lib_, "screen_get_buffer_property_iv");
    read_display_ = (read_display_fn)dlsym(screen_lib_, "screen_read_display");

    if (!create_context_ || !destroy_context_ || !get_context_iv_ || !get_context_pv_ ||
        !get_display_iv_ || !create_pixmap_ || !destroy_pixmap_ || !set_pixmap_iv_ ||
        !create_pixmap_buffer_ || !get_pixmap_pv_ || !get_buffer_pv_ ||
        !get_buffer_iv_ || !read_display_) {
        fprintf(stderr, "capture: required QNX Screen entrypoint missing\n");
        return false;
    }
    return true;
}

bool MmiCaptureSource::find_display() {
    int count = 0;
    if (get_context_iv_(context_, SCREEN_PROPERTY_DISPLAY_COUNT, &count) != 0 || count <= 0) {
        fprintf(stderr, "capture: cannot enumerate Screen displays errno=%d\n", errno);
        return false;
    }

    if (count > 16) count = 16;
    void *displays[16];
    memset(displays, 0, sizeof(displays));
    if (get_context_pv_(context_, SCREEN_PROPERTY_DISPLAYS, displays) != 0) {
        fprintf(stderr, "capture: cannot read Screen display list errno=%d\n", errno);
        return false;
    }

    display_ = 0;
    for (int i = 0; i < count; ++i) {
        int size[2] = {0, 0};
        if (get_display_iv_(displays[i], SCREEN_PROPERTY_SIZE, size) != 0)
            continue;
        if (cfg_.verbose)
            fprintf(stderr, "capture: display[%d] size=%dx%d\n", i, size[0], size[1]);
        if (!display_ && size[0] == cfg_.width && size[1] == cfg_.height)
            display_ = displays[i];
    }

    if (!display_) {
        fprintf(stderr, "capture: no exact %dx%d MMI physical display found\n",
                cfg_.width, cfg_.height);
        return false;
    }
    return true;
}

bool MmiCaptureSource::create_capture_buffer() {
    if (create_pixmap_(&pixmap_, context_) != 0 || !pixmap_) {
        fprintf(stderr, "capture: screen_create_pixmap failed errno=%d\n", errno);
        return false;
    }

    const int usage = SCREEN_USAGE_READ | SCREEN_USAGE_NATIVE;
    const int format = SCREEN_FORMAT_RGBA8888;
    int size[2] = {cfg_.width, cfg_.height};

    if (set_pixmap_iv_(pixmap_, SCREEN_PROPERTY_USAGE, &usage) != 0 ||
        set_pixmap_iv_(pixmap_, SCREEN_PROPERTY_FORMAT, &format) != 0 ||
        set_pixmap_iv_(pixmap_, SCREEN_PROPERTY_BUFFER_SIZE, size) != 0 ||
        create_pixmap_buffer_(pixmap_) != 0 ||
        get_pixmap_pv_(pixmap_, SCREEN_PROPERTY_RENDER_BUFFERS, &buffer_) != 0 || !buffer_ ||
        get_buffer_pv_(buffer_, SCREEN_PROPERTY_POINTER, (void **)&pixels_) != 0 || !pixels_ ||
        get_buffer_iv_(buffer_, SCREEN_PROPERTY_STRIDE, &stride_) != 0 ||
        stride_ < cfg_.width * 4) {
        fprintf(stderr, "capture: pixmap/buffer setup failed stride=%d errno=%d\n",
                stride_, errno);
        return false;
    }

    return true;
}

bool MmiCaptureSource::init() {
    shutdown();

    if (cfg_.width <= 0 || cfg_.height <= 0) return false;
    if (!open_screen() || !resolve_api()) {
        shutdown();
        return false;
    }

    if (create_context_(&context_, SCREEN_DISPLAY_MANAGER_CONTEXT) != 0) {
        context_ = 0;
        if (create_context_(&context_, SCREEN_WINDOW_MANAGER_CONTEXT) != 0) {
            fprintf(stderr, "capture: cannot create manager-capable Screen context errno=%d\n", errno);
            shutdown();
            return false;
        }
        fprintf(stderr, "capture: DISPLAY_MANAGER_CONTEXT rejected; using WINDOW_MANAGER_CONTEXT\n");
    }

    if (!find_display() || !create_capture_buffer()) {
        shutdown();
        return false;
    }

    frame_count_ = 0;
    ready_ = true;
    fprintf(stderr,
            "capture: ready source=%dx%d stride=%d format=%s\n",
            cfg_.width, cfg_.height, stride_,
            cfg_.format == PIXEL_FORMAT_BGRA8888 ? "BGRA8888" : "RGBA8888");
    return true;
}

bool MmiCaptureSource::read_frame(VideoFrame *frame) {
    if (!ready_ || !frame || !display_ || !buffer_ || !pixels_) return false;

    if (read_display_(display_, buffer_, 0, (const int *)0, 0) != 0) {
        if (cfg_.verbose)
            fprintf(stderr, "capture: screen_read_display failed errno=%d\n", errno);
        return false;
    }

    frame->data = pixels_;
    frame->width = cfg_.width;
    frame->height = cfg_.height;
    frame->stride = stride_;
    frame->format = cfg_.format;
    frame->timestamp_us = now_us();
    ++frame_count_;
    return true;
}

void MmiCaptureSource::shutdown() {
    ready_ = false;
    pixels_ = 0;
    buffer_ = 0;
    display_ = 0;
    stride_ = 0;
    frame_count_ = 0;

    if (pixmap_ && destroy_pixmap_) {
        destroy_pixmap_(pixmap_);
    }
    pixmap_ = 0;

    if (context_ && destroy_context_) {
        destroy_context_(context_);
    }
    context_ = 0;

    if (screen_lib_) {
        dlclose(screen_lib_);
    }
    screen_lib_ = 0;

    create_context_ = 0;
    destroy_context_ = 0;
    get_context_iv_ = 0;
    get_context_pv_ = 0;
    get_display_iv_ = 0;
    create_pixmap_ = 0;
    destroy_pixmap_ = 0;
    set_pixmap_iv_ = 0;
    create_pixmap_buffer_ = 0;
    get_pixmap_pv_ = 0;
    get_buffer_pv_ = 0;
    get_buffer_iv_ = 0;
    read_display_ = 0;
}
