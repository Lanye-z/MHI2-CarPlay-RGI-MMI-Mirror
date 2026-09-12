#include "v2_options.h"
#include "v2_runtime.h"
#include <stdio.h>

int main(int argc,char **argv){
    Options opt;
    if(!v2_parse_options(argc,argv,&opt)){v2_usage(argv[0]);return 2;}
    if(opt.mode==RUN_MODE_NONE){fprintf(stderr,"No mode selected. Use --mmi or --test.\n\n");v2_usage(argv[0]);return 0;}
    v2_install_signal_handlers(); setvbuf(stderr,0,_IOLBF,0);
    fprintf(stderr,
      "MHI2Q MMI Mirror V2.2 / JAVA80\n"
      "mode=%s capture=1024x480/BGRA output=1440x455 displayable=3\n"
      "hmi_poll=%dms capture_recover=%dms context_owner=java native_context_routing=removed\n"
      "final-contract: ctx80={98,101,102,3}; displayable3=BaseVideo, displayable98=RGI\n",
      opt.mode==RUN_MODE_MMI?"MMI":"TEST-GRID",opt.hmi_poll_ms,opt.capture_recover_ms);
    return opt.mode==RUN_MODE_TEST?v2_run_test_grid(opt):v2_run_mmi(opt);
}
