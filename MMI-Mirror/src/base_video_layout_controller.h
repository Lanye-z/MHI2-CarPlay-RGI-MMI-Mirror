#ifndef BASE_VIDEO_LAYOUT_CONTROLLER_H
#define BASE_VIDEO_LAYOUT_CONTROLLER_H

#include "cluster_layout_state.h"

struct BaseVideoGeometryProfile {
    float scale;
    int offset_x;
    int offset_y;
};

struct BaseVideoLayoutProfiles {
    BaseVideoGeometryProfile classic_full;
    BaseVideoGeometryProfile classic_small;
    BaseVideoGeometryProfile sport_full;
    BaseVideoGeometryProfile sport_small;
};

struct BaseVideoDestination {
    int x;
    int y;
    int width;
    int height;
    float applied_scale;
    int offset_x;
    int offset_y;
    const char *profile_name;
};

class BaseVideoLayoutController {
public:
    BaseVideoLayoutController(int source_width,
                              int source_height,
                              int output_width,
                              int output_height,
                              const BaseVideoLayoutProfiles &profiles);

    bool resolve(const ClusterLayoutState &state,
                 BaseVideoDestination *destination) const;

    static const char *profile_name(const ClusterLayoutState &state);

private:
    const BaseVideoGeometryProfile &profile_for(const ClusterLayoutState &state) const;

    int source_width_;
    int source_height_;
    int output_width_;
    int output_height_;
    BaseVideoLayoutProfiles profiles_;
};

#endif
