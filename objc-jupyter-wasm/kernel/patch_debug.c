#include "objc_interp_types.h"
extern void host_log(const char *msg, int len);
void my_debug_log(const char *msg) {
    int len = 0;
    while(msg[len]) len++;
    host_log(msg, len);
}
