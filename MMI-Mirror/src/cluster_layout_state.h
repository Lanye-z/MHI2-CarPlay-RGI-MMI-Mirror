#ifndef CLUSTER_LAYOUT_STATE_H
#define CLUSTER_LAYOUT_STATE_H

#include <stddef.h>

enum ClusterLayoutSkin {
    CLUSTER_LAYOUT_UNKNOWN = 0,
    CLUSTER_LAYOUT_CLASSIC,
    CLUSTER_LAYOUT_SPORT
};

enum ClusterViewMode {
    CLUSTER_VIEW_UNKNOWN = 0,
    CLUSTER_VIEW_FULL,
    CLUSTER_VIEW_SMALL
};

struct ClusterLayoutState {
    ClusterLayoutSkin layout;
    ClusterViewMode view;

    ClusterLayoutState()
        : layout(CLUSTER_LAYOUT_UNKNOWN), view(CLUSTER_VIEW_UNKNOWN) {}

    ClusterLayoutState(ClusterLayoutSkin l, ClusterViewMode v)
        : layout(l), view(v) {}

    bool complete() const {
        return layout != CLUSTER_LAYOUT_UNKNOWN && view != CLUSTER_VIEW_UNKNOWN;
    }

    bool operator==(const ClusterLayoutState &other) const {
        return layout == other.layout && view == other.view;
    }

    bool operator!=(const ClusterLayoutState &other) const {
        return !(*this == other);
    }
};

class ClusterLayoutStateReader {
public:
    explicit ClusterLayoutStateReader(const char *path);

    bool read(ClusterLayoutState *state) const;
    const char *path() const { return path_; }

    static const char *layout_name(ClusterLayoutSkin layout);
    static const char *view_name(ClusterViewMode view);
    static const char *state_name(const ClusterLayoutState &state,
                                  char *buffer, size_t buffer_bytes);

private:
    ClusterLayoutStateReader(const ClusterLayoutStateReader &);
    ClusterLayoutStateReader &operator=(const ClusterLayoutStateReader &);

    char path_[256];
};

#endif
