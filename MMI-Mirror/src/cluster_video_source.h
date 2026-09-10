#ifndef CLUSTER_VIDEO_SOURCE_H
#define CLUSTER_VIDEO_SOURCE_H

#include "video_frame.h"

class ClusterVideoSource {
public:
    virtual ~ClusterVideoSource() {}
    virtual bool init() = 0;
    virtual bool read_frame(VideoFrame *frame) = 0;
    virtual void shutdown() = 0;
    virtual const char *name() const = 0;
};

#endif
