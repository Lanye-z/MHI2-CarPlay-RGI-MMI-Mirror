#include "cluster_video_display.h"

#include <stdio.h>

ClusterVideoDisplay::ClusterVideoDisplay()
    : ready_(false), first_frame_presented_(false), frame_count_(0) {
}

ClusterVideoDisplay::~ClusterVideoDisplay() {
    shutdown();
}

bool ClusterVideoDisplay::init(const Mhi2qBackendConfig &cfg) {
    shutdown();

    if (!backend_.init(cfg)) {
        fprintf(stderr, "display: backend initialization failed\n");
        return false;
    }
    if (!renderer_.init(cfg.width, cfg.height)) {
        fprintf(stderr, "display: GLES renderer initialization failed\n");
        backend_.shutdown();
        return false;
    }

    ready_ = true;
    first_frame_presented_ = false;
    frame_count_ = 0;
    fprintf(stderr,
            "display: ready output=%dx%d displayable=%d context_owner=java\n",
            cfg.width, cfg.height, cfg.displayable_id);
    return true;
}

bool ClusterVideoDisplay::present_uploaded_frame() {
    if (!ready_) return false;

    /* Preserve the vehicle-tested first-frame timing from V2A/V2.2. The old
     * no-op Native route call sat between these two submits; only that call is removed. */
    renderer_.draw();
    backend_.swap();

    if (!first_frame_presented_) {
        renderer_.draw();
        backend_.swap();
        first_frame_presented_ = true;
    }

    ++frame_count_;
    return true;
}

bool ClusterVideoDisplay::present_frame(const VideoFrame &frame) {
    if (!ready_) {
        fprintf(stderr, "display: present_frame called before init\n");
        return false;
    }
    if (!renderer_.upload_frame(frame)) {
        fprintf(stderr, "display: frame texture upload failed\n");
        return false;
    }
    return present_uploaded_frame();
}

bool ClusterVideoDisplay::present_test_grid() {
    if (!ready_) return false;
    renderer_.set_fullscreen_destination();
    if (!renderer_.upload_test_grid(backend_.width(), backend_.height())) {
        fprintf(stderr, "display: diagnostic grid upload failed\n");
        return false;
    }
    return present_uploaded_frame();
}

bool ClusterVideoDisplay::set_destination_rect(int x, int y, int width, int height) {
    if (!ready_) return false;
    return renderer_.set_destination_rect(x, y, width, height);
}

void ClusterVideoDisplay::set_fullscreen_destination() {
    if (ready_) renderer_.set_fullscreen_destination();
}

void ClusterVideoDisplay::refresh() {
    if (!ready_) return;
    renderer_.draw();
    backend_.swap();
}

void ClusterVideoDisplay::shutdown() {
    if (ready_) renderer_.shutdown();
    backend_.shutdown();
    ready_ = false;
    first_frame_presented_ = false;
    frame_count_ = 0;
}
