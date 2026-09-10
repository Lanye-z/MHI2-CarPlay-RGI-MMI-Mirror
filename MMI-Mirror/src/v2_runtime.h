#ifndef V2_RUNTIME_H
#define V2_RUNTIME_H
#include "v2_options.h"
void v2_install_signal_handlers();
int v2_run_test_grid(const Options &opt);
int v2_run_mmi(const Options &opt);
#endif
