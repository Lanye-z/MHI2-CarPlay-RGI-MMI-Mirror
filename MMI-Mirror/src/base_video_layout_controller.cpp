#include "base_video_layout_controller.h"

BaseVideoLayoutController::BaseVideoLayoutController(
        int source_width,
        int source_height,
        int output_width,
        int output_height,
        const BaseVideoLayoutProfiles &profiles)
    : source_width_(source_width),
      source_height_(source_height),
      output_width_(output_width),
      output_height_(output_height),
      profiles_(profiles) {
}

const BaseVideoGeometryProfile &BaseVideoLayoutController::profile_for(
        const ClusterLayoutState &state) const {
    if (state.layout == CLUSTER_LAYOUT_SPORT) {
        return state.view == CLUSTER_VIEW_SMALL
            ? profiles_.sport_small : profiles_.sport_full;
    }
    return state.view == CLUSTER_VIEW_SMALL
        ? profiles_.classic_small : profiles_.classic_full;
}

const char *BaseVideoLayoutController::profile_name(const ClusterLayoutState &state) {
    if (state.layout == CLUSTER_LAYOUT_SPORT)
        return state.view == CLUSTER_VIEW_SMALL ? "SPORT_SMALL" : "SPORT_FULL";
    return state.view == CLUSTER_VIEW_SMALL ? "CLASSIC_SMALL" : "CLASSIC_FULL";
}

bool BaseVideoLayoutController::resolve(const ClusterLayoutState &state,
                                        BaseVideoDestination *destination) const {
    if (!destination || source_width_ <= 0 || source_height_ <= 0 ||
        output_width_ <= 0 || output_height_ <= 0) {
        return false;
    }

    const BaseVideoGeometryProfile &profile = profile_for(state);
    if (profile.scale <= 0.0f) return false;

    float scale = profile.scale;
    const float fit_x = (float)output_width_ / (float)source_width_;
    const float fit_y = (float)output_height_ / (float)source_height_;
    const float max_scale = fit_x < fit_y ? fit_x : fit_y;
    if (scale > max_scale) scale = max_scale;

    int width = (int)((float)source_width_ * scale + 0.5f);
    int height = (int)((float)source_height_ * scale + 0.5f);
    if (width < 1) width = 1;
    if (height < 1) height = 1;

    int x = (output_width_ - width) / 2 + profile.offset_x;
    int y = (output_height_ - height) / 2 + profile.offset_y;

    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + width > output_width_) x = output_width_ - width;
    if (y + height > output_height_) y = output_height_ - height;

    destination->x = x;
    destination->y = y;
    destination->width = width;
    destination->height = height;
    destination->applied_scale = scale;
    destination->offset_x = profile.offset_x;
    destination->offset_y = profile.offset_y;
    destination->profile_name = profile_name(state);
    return true;
}
