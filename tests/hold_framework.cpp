#include <dlfcn.h>
#include <cstdio>
#include <unistd.h>
// Disposable-runner fixture: a mapped framework can remain in use without an
// ordinary open descriptor. Keep it loaded until the test terminates us.
int main(int argc,char** argv) {
    if(argc!=3)return 2;
    if(!dlopen(argv[1],RTLD_NOW|RTLD_LOCAL)){fprintf(stderr,"%s\n",dlerror());return 1;}
    FILE* ready=fopen(argv[2],"w");if(!ready)return 1;fclose(ready);
    for(;;)pause();
}
