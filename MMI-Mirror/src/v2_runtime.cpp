#include "v2_runtime.h"
#include "cluster_layout_state.h"
#include "cluster_video_display.h"

#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>

static const char *kHmiStateFile = "/tmp/mmi-mirror-hmi.state";
static const char *kBaseVideoReadyFile = "/tmp/mmi-mirror-basevideo.ready";

static volatile sig_atomic_t g_stop=0;
static void on_signal(int){ g_stop=1; }
void v2_install_signal_handlers(){ signal(SIGINT,on_signal); signal(SIGTERM,on_signal); signal(SIGHUP,on_signal); }

static unsigned long long now_us(){ struct timeval tv; if(gettimeofday(&tv,0)!=0)return 0; return (unsigned long long)(unsigned long)tv.tv_sec*1000000ULL+(unsigned long long)(unsigned long)tv.tv_usec; }

static void set_ready_marker(bool ready) {
    if (!ready) {
        unlink(kBaseVideoReadyFile);
        return;
    }
    FILE *fp = fopen(kBaseVideoReadyFile, "w");
    if (!fp) {
        fprintf(stderr, "state: WARN could not create BaseVideo ready marker %s\n", kBaseVideoReadyFile);
        return;
    }
    fprintf(fp, "ready=1\npid=%ld\n", (long)getpid());
    fclose(fp);
}

static bool apply_layout(ClusterVideoDisplay *display,const BaseVideoLayoutController &ctl,const ClusterLayoutState &state,const char *source){
    BaseVideoDestination d; if(!ctl.resolve(state,&d))return false; if(!display->set_destination_rect(d.x,d.y,d.width,d.height))return false;
    char name[64]; fprintf(stderr,"layout: state=%s profile=%s source=%s scale=%.3f dst=%dx%d@(%d,%d) offset=(%d,%d)\n",
      ClusterLayoutStateReader::state_name(state,name,sizeof(name)),d.profile_name,source?source:"unknown",d.applied_scale,d.width,d.height,d.x,d.y,d.offset_x,d.offset_y); return true;
}

static bool acquire_first_frame(MmiCaptureSource *capture,VideoFrame *frame,int wait_ms){
    const int step=200; int waited=0, failures=0;
    while(!g_stop&&waited<wait_ms){
        if(!capture->is_ready()){ if(!capture->init()){usleep(step*1000);waited+=step;continue;} failures=0; }
        if(capture->read_frame(frame))return true;
        if(++failures>=5){capture->shutdown();failures=0;}
        usleep(step*1000); waited+=step;
    }
    return false;
}

int v2_run_test_grid(const Options &opt){
    ClusterVideoDisplay display; if(!display.init(opt.backend))return 3; if(!display.present_test_grid()){display.shutdown();return 4;}
    int elapsed=0; while(!g_stop){sleep(1);display.refresh();if(opt.test_seconds>0&&++elapsed>=opt.test_seconds)break;} display.shutdown(); return 0;
}

int v2_run_mmi(const Options &opt){
    set_ready_marker(false);
    MmiCaptureSource capture(opt.capture); VideoFrame frame;
    fprintf(stderr,"main: JAVA80; Native owns pixels only and contains no Cluster context routing\n");
    fprintf(stderr,"main: waiting for first physical MMI frame before publishing BaseVideo readiness\n");
    if(!acquire_first_frame(&capture,&frame,opt.capture_wait_ms)){fprintf(stderr,"main: no valid MMI frame within %d ms; VC left untouched\n",opt.capture_wait_ms);capture.shutdown();return 3;}

    ClusterVideoDisplay display; if(!display.init(opt.backend)){capture.shutdown();return 4;}
    ClusterLayoutStateReader reader(kHmiStateFile); ClusterLayoutState state_now, observed; const char *source="fallback";
    if(reader.read(&observed)){state_now=observed;source="observer";} else {state_now=ClusterLayoutState(CLUSTER_LAYOUT_CLASSIC,CLUSTER_VIEW_FULL);fprintf(stderr,"hmi: no valid state at %s; using CLASSIC_FULL fallback until observer appears\n",reader.path());}
    BaseVideoLayoutController layout(opt.capture.width,opt.capture.height,opt.backend.width,opt.backend.height,opt.profiles);
    if(opt.fullscreen){display.set_fullscreen_destination();fprintf(stderr,"layout: fullscreen stretch %dx%d\n",opt.backend.width,opt.backend.height);} else if(!apply_layout(&display,layout,state_now,source)){display.shutdown();capture.shutdown();return 5;}

    if(!display.present_frame(frame)){display.shutdown();capture.shutdown();return 6;}
    set_ready_marker(true);
    fprintf(stderr,"state: BaseVideo ready marker published at %s; Java controller owns ctx80\n", kBaseVideoReadyFile);

    const unsigned long long period=1000000ULL/(unsigned long long)opt.fps;
    const unsigned long long hard=(unsigned long long)(unsigned int)opt.capture_recover_ms*1000ULL;
    const unsigned long long hmi_period=(unsigned long long)(unsigned int)opt.hmi_poll_ms*1000ULL;
    int failures=0; bool degraded=false; unsigned long long failure_start=0,last_hmi=0,stats_start=now_us(); unsigned long stats_frames=0; bool observer_seen=!strcmp(source,"observer");

    while(!g_stop){
        const unsigned long long frame_start=now_us();
        if(!opt.fullscreen&&frame_start-last_hmi>=hmi_period){
            last_hmi=frame_start;
            if(reader.read(&observed)){
                if(!observer_seen){observer_seen=true;fprintf(stderr,"hmi: observer state became available at %s\n",reader.path());}
                if(observed!=state_now){
                    char a[64],b[64];
                    fprintf(stderr,"hmi: state %s -> %s\n",ClusterLayoutStateReader::state_name(state_now,a,sizeof(a)),ClusterLayoutStateReader::state_name(observed,b,sizeof(b)));
                    state_now=observed;
                    if(!apply_layout(&display,layout,state_now,"observer")){fprintf(stderr,"main: invalid dynamic geometry; stopping safely\n");break;}
                }
            }
        }

        if(!capture.read_frame(&frame)){
            ++failures; if(failure_start==0)failure_start=frame_start;
            if(!degraded&&failures>=opt.failure_threshold){degraded=true;fprintf(stderr,"main: capture temporarily unavailable (%d failures); freeze last frame and retry slowly\n",failures);}
            const unsigned long long failed_for=now_us()-failure_start;
            if(failed_for>=hard){
                fprintf(stderr,"main: capture unavailable for %llu ms; withdraw BaseVideo readiness and fully reacquire source\n",failed_for/1000ULL);
                set_ready_marker(false); capture.shutdown();
                if(!acquire_first_frame(&capture,&frame,opt.capture_wait_ms)){fprintf(stderr,"main: capture did not recover; stopping safely\n");break;}
                if(!display.present_frame(frame)){fprintf(stderr,"main: recovered frame could not be presented\n");break;}
                set_ready_marker(true);
                fprintf(stderr,"main: capture recovered; BaseVideo readiness republished\n"); failures=0;degraded=false;failure_start=0;
            } else if(degraded){usleep(100000);continue;}
        } else {
            if(degraded)fprintf(stderr,"main: capture resumed after %d failures without renderer restart\n",failures);
            failures=0;degraded=false;failure_start=0; if(!display.present_frame(frame)){fprintf(stderr,"main: display presentation failed; stopping safely\n");break;} ++stats_frames;
        }

        const unsigned long long now=now_us();
        if(opt.verbose&&now-stats_start>=10000000ULL){const unsigned long long span=now-stats_start;const unsigned long fps100=span?(unsigned long)(((unsigned long long)stats_frames*100000000ULL)/span):0;char n[64];fprintf(stderr,"stats: fps=%lu.%02lu capture_frames=%lu presented_frames=%lu stride=%d hmi=%s\n",fps100/100,fps100%100,capture.frame_count(),display.frame_count(),capture.stride(),ClusterLayoutStateReader::state_name(state_now,n,sizeof(n)));stats_start=now;stats_frames=0;} else if(!opt.verbose&&now-stats_start>=10000000ULL){stats_start=now;stats_frames=0;}
        const unsigned long long spent=now_us()-frame_start; if(spent<period)usleep((unsigned int)(period-spent));
    }

    set_ready_marker(false);
    display.shutdown(); capture.shutdown();
    fprintf(stderr,"state: BaseVideo stopped; Java controller will release ctx80 when no RGI demand remains\n");
    return 0;
}
