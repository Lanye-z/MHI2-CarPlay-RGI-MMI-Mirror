#include "v2_options.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int kOutputWidth = 1440;
static const int kOutputHeight = 455;
static const int kBaseVideoDisplayable = 3;
static const int kCaptureWidth = 1024;
static const int kCaptureHeight = 480;

static void set_profile(BaseVideoGeometryProfile *p, float scale, int x, int y) {
    p->scale = scale; p->offset_x = x; p->offset_y = y;
}
static void set_all_scales(BaseVideoLayoutProfiles *p, float s) {
    p->classic_full.scale=s; p->classic_small.scale=s; p->sport_full.scale=s; p->sport_small.scale=s;
}
static void set_all_x(BaseVideoLayoutProfiles *p, int x) {
    p->classic_full.offset_x=x; p->classic_small.offset_x=x; p->sport_full.offset_x=x; p->sport_small.offset_x=x;
}
static void set_all_y(BaseVideoLayoutProfiles *p, int y) {
    p->classic_full.offset_y=y; p->classic_small.offset_y=y; p->sport_full.offset_y=y; p->sport_small.offset_y=y;
}

void v2_defaults(Options *o) {
    o->mode=RUN_MODE_NONE; o->verbose=false; o->fullscreen=false;
    o->test_seconds=0; o->fps=30; o->capture_wait_ms=10000; o->failure_threshold=5;
    o->capture_recover_ms=3000; o->hmi_poll_ms=100;
    set_profile(&o->profiles.classic_full,0.80f,0,0);
    set_profile(&o->profiles.classic_small,0.80f,0,0);
    set_profile(&o->profiles.sport_full,0.80f,0,0);
    set_profile(&o->profiles.sport_small,0.80f,0,0);
    o->capture.width=kCaptureWidth; o->capture.height=kCaptureHeight;
    o->capture.format=PIXEL_FORMAT_BGRA8888; o->capture.verbose=false;
    o->backend.width=kOutputWidth; o->backend.height=kOutputHeight;
    o->backend.displayable_id=kBaseVideoDisplayable; o->backend.verbose=false;
}

void v2_usage(const char *a) {
    fprintf(stderr,
      "MHI2Q MMI Mirror V2.2 / JAVA80\n\n"
      "Usage: %s --mmi [options]\n       %s --test [options]\n\n"
      "Fixed production contract: capture=1024x480/BGRA, output=1440x455, displayable=3, Java owns ctx80.\n"
      "Runtime: --hmi-poll-ms MS --capture-recover-ms MS --fps N\n"
      "Profiles: --classic-full-scale/offset-x/offset-y, --classic-small-*, --sport-full-*, --sport-small-*\n"
      "Legacy geometry aliases: --content-scale --offset-x --offset-y\n"
      "Other: --fullscreen --test-seconds --verbose --help\n", a, a);
}

static bool take_int(int argc,char **argv,int *i,int *out){ if(*i+1>=argc)return false; *out=atoi(argv[++(*i)]); return true; }
static bool take_float(int argc,char **argv,int *i,float *out){ if(*i+1>=argc)return false; *out=(float)atof(argv[++(*i)]); return true; }

bool v2_parse_options(int argc, char **argv, Options *o) {
    v2_defaults(o);
    for(int i=1;i<argc;++i){
        const char *a=argv[i];
        if(!strcmp(a,"--mmi")){ if(o->mode!=RUN_MODE_NONE&&o->mode!=RUN_MODE_MMI)return false; o->mode=RUN_MODE_MMI; }
        else if(!strcmp(a,"--test")){ if(o->mode!=RUN_MODE_NONE&&o->mode!=RUN_MODE_TEST)return false; o->mode=RUN_MODE_TEST; }
        else if(!strcmp(a,"--test-seconds")){ if(!take_int(argc,argv,&i,&o->test_seconds))return false; }
        else if(!strcmp(a,"--capture-recover-ms")){ if(!take_int(argc,argv,&i,&o->capture_recover_ms))return false; }
        else if(!strcmp(a,"--fps")){ if(!take_int(argc,argv,&i,&o->fps))return false; }
        else if(!strcmp(a,"--hmi-poll-ms")){ if(!take_int(argc,argv,&i,&o->hmi_poll_ms))return false; }
#define PF(name,field) else if(!strcmp(a,name)){ if(!take_float(argc,argv,&i,&o->profiles.field.scale))return false; }
#define PX(name,field) else if(!strcmp(a,name)){ if(!take_int(argc,argv,&i,&o->profiles.field.offset_x))return false; }
#define PY(name,field) else if(!strcmp(a,name)){ if(!take_int(argc,argv,&i,&o->profiles.field.offset_y))return false; }
        PF("--classic-full-scale",classic_full) PX("--classic-full-offset-x",classic_full) PY("--classic-full-offset-y",classic_full)
        PF("--classic-small-scale",classic_small) PX("--classic-small-offset-x",classic_small) PY("--classic-small-offset-y",classic_small)
        PF("--sport-full-scale",sport_full) PX("--sport-full-offset-x",sport_full) PY("--sport-full-offset-y",sport_full)
        PF("--sport-small-scale",sport_small) PX("--sport-small-offset-x",sport_small) PY("--sport-small-offset-y",sport_small)
#undef PF
#undef PX
#undef PY
        else if(!strcmp(a,"--content-scale")){ float s; if(!take_float(argc,argv,&i,&s))return false; set_all_scales(&o->profiles,s); }
        else if(!strcmp(a,"--offset-x")){ int x; if(!take_int(argc,argv,&i,&x))return false; set_all_x(&o->profiles,x); }
        else if(!strcmp(a,"--offset-y")){ int y; if(!take_int(argc,argv,&i,&y))return false; set_all_y(&o->profiles,y); }
        else if(!strcmp(a,"--fullscreen")){ o->fullscreen=true; }
        else if(!strcmp(a,"--verbose")){ o->verbose=true; o->capture.verbose=true; o->backend.verbose=true; }
        else if(!strcmp(a,"--help")||!strcmp(a,"-h")){ v2_usage(argv[0]); exit(0); }
        else { fprintf(stderr,"Unknown option: %s\n",a); return false; }
    }
    const BaseVideoGeometryProfile *p[]={&o->profiles.classic_full,&o->profiles.classic_small,&o->profiles.sport_full,&o->profiles.sport_small};
    for(unsigned int i=0;i<sizeof(p)/sizeof(p[0]);++i) if(p[i]->scale<=0.0f||p[i]->scale>4.0f)return false;
    if(o->capture_recover_ms<500||o->capture_recover_ms>60000||o->hmi_poll_ms<20||o->hmi_poll_ms>5000||
       o->fps<=0||o->fps>60||o->test_seconds<0) return false;
    return true;
}
