#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void objc_kernel_init(void);
extern int objc_kernel_eval(const char *code, char **out_json, int *out_len);

int main() {
    objc_kernel_init();
    
    const char *code = "@interface IvarTest : NSObject { @public int field; } @end\n"
                       "@implementation IvarTest - (instancetype)init { self = [super init]; field = 42; return self; } @end\n"
                       "IvarTest *t = [IvarTest new];\n"
                       "NSLog(@\"%d\", t->field);";
                       
    char *out_json = NULL;
    int out_len = 0;
    
    printf("Evaluating...\n");
    objc_kernel_eval(code, &out_json, &out_len);
    printf("Done!\n");
    if (out_json) {
        printf("Output: %s\n", out_json);
        free(out_json);
    }
    return 0;
}
