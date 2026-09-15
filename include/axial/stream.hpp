#pragma once
#include "transport.hpp"
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <dlfcn.h>

namespace sn {
// Dispatch cancellation and callbacks can unwind after a client calls dlclose.
// Keep framework code mapped for the process lifetime; resources still stop at
// Cleanup/NlClose. This runs once at adapter registration, never on input.
inline void keepCallbackCodeMapped(const void* entry) {
    Dl_info info{};
    if(dladdr(entry,&info)&&info.dli_fname)
        if(void* handle=dlopen(info.dli_fname,RTLD_NOW|RTLD_LOCAL|RTLD_NOLOAD|RTLD_NODELETE))dlclose(handle);
}
// All methods and callbacks run on queue. Lifetime is owned by the adapter.
class Stream {
    int fd=-1;
    dispatch_source_t source=nullptr,retry=nullptr;
    Event incoming{};
    size_t offset=0;
    uint32_t flags;
    void (*callback)(void*,const Event&);
    void* context;
    dispatch_queue_t queue;
    void disconnected() {
        if(source){dispatch_source_cancel(source);source=nullptr;}
        if(fd>=0){fd=-1;Event e;e.kind=Kind::reset;e.flags=Flags::disconnected;e.received=now();callback(context,e);}
        offset=0;
    }
    void connect() {
        if(fd>=0)return;
        fd=openEvents(flags,true);if(fd<0)return;
        source=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,fd,0,queue);
        int ownedFD=fd;
        dispatch_source_set_cancel_handler(source,^{close(ownedFD);});
        Stream* self=this;
        dispatch_source_set_event_handler(source,^{self->read();});
        dispatch_resume(source);
    }
    void read() {
        while(fd>=0) {
            ssize_t n=recv(fd,reinterpret_cast<char*>(&incoming)+offset,sizeof(Event)-offset,0);
            if(n<0&&(errno==EAGAIN||errno==EWOULDBLOCK))return;
            if(n<0&&errno==EINTR)continue;
            if(n<=0){disconnected();return;}
            offset+=size_t(n);
            if(offset!=sizeof(Event))continue;
            offset=0;
            if(!valid(incoming)){disconnected();return;}
            Event e=incoming;callback(context,e);
        }
    }
public:
    Stream(dispatch_queue_t q,void (*cb)(void*,const Event&),void* ctx,uint32_t f=0):flags(f),callback(cb),context(ctx),queue(q){}
    void start() {
        if(retry)return;
        retry=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
        Stream* self=this;
        dispatch_source_set_timer(retry,dispatch_time(DISPATCH_TIME_NOW,0),NSEC_PER_SEC,100*NSEC_PER_MSEC);
        dispatch_source_set_event_handler(retry,^{self->connect();});dispatch_resume(retry);
    }
    void stop() {
        if(retry){dispatch_source_cancel(retry);retry=nullptr;}
        if(source){dispatch_source_cancel(source);source=nullptr;}
        fd=-1;offset=0;
    }
    ~Stream(){stop();}
};
}
