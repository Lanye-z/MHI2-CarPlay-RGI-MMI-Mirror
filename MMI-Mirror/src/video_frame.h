#ifndef VIDEO_FRAME_H
#define VIDEO_FRAME_H

enum PixelFormat {
    PIXEL_FORMAT_RGBA8888 = 0,
    PIXEL_FORMAT_BGRA8888 = 1,
    PIXEL_FORMAT_RGBX8888 = 2,
    PIXEL_FORMAT_BGRX8888 = 3
};

struct VideoFrame {
    const unsigned char *data;
    int width;
    int height;
    int stride;
    PixelFormat format;
    unsigned long long timestamp_us;

    VideoFrame()
        : data(0), width(0), height(0), stride(0),
          format(PIXEL_FORMAT_RGBA8888), timestamp_us(0) {
    }
};

#endif
