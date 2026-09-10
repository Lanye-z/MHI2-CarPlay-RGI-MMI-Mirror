#include "cluster_layout_state.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

static char *trim(char *s) {
    if (!s) return s;
    while (*s && isspace((unsigned char)*s)) ++s;
    char *end = s + strlen(s);
    while (end > s && isspace((unsigned char)end[-1])) --end;
    *end = '\0';
    return s;
}

static bool equals_ci(const char *a, const char *b) {
    if (!a || !b) return false;
    while (*a && *b) {
        if (toupper((unsigned char)*a) != toupper((unsigned char)*b))
            return false;
        ++a;
        ++b;
    }
    return *a == '\0' && *b == '\0';
}

ClusterLayoutStateReader::ClusterLayoutStateReader(const char *path) {
    path_[0] = '\0';
    if (!path || !*path) return;
    strncpy(path_, path, sizeof(path_) - 1);
    path_[sizeof(path_) - 1] = '\0';
}

bool ClusterLayoutStateReader::read(ClusterLayoutState *state) const {
    if (!state || !path_[0]) return false;

    FILE *fp = fopen(path_, "r");
    if (!fp) return false;

    ClusterLayoutState parsed;
    char line[192];
    while (fgets(line, sizeof(line), fp)) {
        char *text = trim(line);
        if (!*text || *text == '#') continue;

        char *eq = strchr(text, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = trim(text);
        char *value = trim(eq + 1);

        if (equals_ci(key, "layout") || equals_ci(key, "skin")) {
            if (equals_ci(value, "CLASSIC"))
                parsed.layout = CLUSTER_LAYOUT_CLASSIC;
            else if (equals_ci(value, "SPORT"))
                parsed.layout = CLUSTER_LAYOUT_SPORT;
            else
                parsed.layout = CLUSTER_LAYOUT_UNKNOWN;
        } else if (equals_ci(key, "view") || equals_ci(key, "view_mode")) {
            if (equals_ci(value, "FULL") || equals_ci(value, "FULLSCREEN"))
                parsed.view = CLUSTER_VIEW_FULL;
            else if (equals_ci(value, "SMALL") || equals_ci(value, "SMALLSCREEN"))
                parsed.view = CLUSTER_VIEW_SMALL;
            else
                parsed.view = CLUSTER_VIEW_UNKNOWN;
        }
    }
    fclose(fp);

    if (!parsed.complete()) return false;
    *state = parsed;
    return true;
}

const char *ClusterLayoutStateReader::layout_name(ClusterLayoutSkin layout) {
    switch (layout) {
        case CLUSTER_LAYOUT_CLASSIC: return "CLASSIC";
        case CLUSTER_LAYOUT_SPORT: return "SPORT";
        default: return "UNKNOWN";
    }
}

const char *ClusterLayoutStateReader::view_name(ClusterViewMode view) {
    switch (view) {
        case CLUSTER_VIEW_FULL: return "FULL";
        case CLUSTER_VIEW_SMALL: return "SMALL";
        default: return "UNKNOWN";
    }
}

const char *ClusterLayoutStateReader::state_name(const ClusterLayoutState &state,
                                                  char *buffer,
                                                  size_t buffer_bytes) {
    if (!buffer || buffer_bytes == 0) return "UNKNOWN";
    snprintf(buffer, buffer_bytes, "%s_%s",
             layout_name(state.layout), view_name(state.view));
    buffer[buffer_bytes - 1] = '\0';
    return buffer;
}
