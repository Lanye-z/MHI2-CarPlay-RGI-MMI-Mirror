#ifndef GL_RENDERER_H
#define GL_RENDERER_H

#include "video_frame.h"
#include <GLES2/gl2.h>
#include <stddef.h>

class GlRenderer {
public:
    GlRenderer();
    ~GlRenderer();

    bool init(int output_width, int output_height);
    bool upload_frame(const VideoFrame &frame);
    bool upload_rgba(const unsigned char *rgba, int width, int height);
    bool upload_test_grid(int width, int height);

    /* Destination rectangle uses output-pixel coordinates with top-left origin. */
    bool set_destination_rect(int x, int y, int width, int height);
    void set_fullscreen_destination();

    void draw();
    void shutdown();

private:
    GlRenderer(const GlRenderer &);
    GlRenderer &operator=(const GlRenderer &);

    bool compile_shader(GLuint shader, const char *source, const char *name);
    bool ensure_upload_buffer(size_t bytes);
    bool upload_packed_rgba_bytes(const unsigned char *pixels,
                                  int width, int height,
                                  bool swap_rb);

    GLuint program_;
    GLuint vertex_shader_;
    GLuint fragment_shader_;
    GLuint texture_;
    GLint attr_position_;
    GLint attr_texcoord_;
    GLint uniform_texture_;
    GLint uniform_swap_rb_;
    int texture_width_;
    int texture_height_;
    int output_width_;
    int output_height_;
    bool swap_rb_;
    bool ready_;

    GLfloat vertices_[8];
    unsigned char *upload_buffer_;
    size_t upload_buffer_bytes_;
};

#endif
