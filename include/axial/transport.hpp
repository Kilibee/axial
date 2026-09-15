#pragma once
#include "core.hpp"
#include <cerrno>
#include <cstdlib>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <poll.h>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

namespace sn {
inline uint64_t now() noexcept {
    static const mach_timebase_info_data_t tb=[] { mach_timebase_info_data_t t; mach_timebase_info(&t); return t; }();
    return uint64_t((__uint128_t(mach_continuous_time())*tb.numer)/tb.denom);
}
inline std::string socketPath(bool control=false) {
    const char* custom=getenv("AXIAL_SOCKET");
    std::string p=custom ? custom : "/tmp/axial-"+std::to_string(getuid())+"/events";
    return control ? p+".control" : p;
}
inline void socketOptions(int fd) {
    int yes=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    fcntl(fd,F_SETFD,FD_CLOEXEC);
}
inline bool waitSocket(int fd,short events,uint64_t deadline) {
    for(;;) {
        uint64_t time=now();if(time>=deadline){errno=ETIMEDOUT;return false;}
        pollfd p{fd,events,0};int ms=int(std::min<uint64_t>((deadline-time+999999)/1000000,2000));
        int result=poll(&p,1,ms);
        if(result<0&&errno==EINTR)continue;
        if(result>0)return !(p.revents&POLLNVAL);
        if(result==0)errno=ETIMEDOUT;
        return false;
    }
}
// Connect before restoring blocking mode, so a full listener backlog cannot
// hang callers indefinitely. Dispatch-driven readers use the nonblocking mode.
inline int connectSocket(bool control=false,int timeoutMS=250,bool nonblocking=false) {
    int fd=socket(AF_UNIX,SOCK_STREAM,0); if(fd<0)return -1;
    socketOptions(fd);
    sockaddr_un a{}; a.sun_family=AF_UNIX; auto p=socketPath(control);
    if(p.size()>=sizeof(a.sun_path)) {close(fd);errno=ENAMETOOLONG;return -1;}
    memcpy(a.sun_path,p.c_str(),p.size()+1);
    fcntl(fd,F_SETFL,O_NONBLOCK);
    if(connect(fd,reinterpret_cast<sockaddr*>(&a),sizeof(a))<0){
        int error=errno;
        if((error!=EINPROGRESS&&error!=EINTR)||timeoutMS<=0||!waitSocket(fd,POLLOUT,now()+uint64_t(timeoutMS)*1000000)){close(fd);return -1;}
        socklen_t size=sizeof(error);
        if(getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&size)||error){close(fd);if(error)errno=error;return -1;}
    }
    if(!nonblocking)fcntl(fd,F_SETFL,0);
    return fd;
}
inline bool writeAll(int fd,const void* data,size_t size) {
    const char* p=static_cast<const char*>(data);
    while(size) {auto n=send(fd,p,size,0); if(n<0&&errno==EINTR)continue;
        if(n<=0)return false; p+=n;size-=size_t(n);}
    return true;
}
inline bool readAll(int fd,void* data,size_t size) {
    char* p=static_cast<char*>(data);
    while(size) {auto n=recv(fd,p,size,0); if(n<0&&errno==EINTR)continue;
        if(n<=0)return false; p+=n;size-=size_t(n);}
    return true;
}
inline int openEvents(uint32_t flags=0,bool nonblocking=false) {
    int fd=connectSocket(false,nonblocking?0:250,nonblocking); if(fd<0)return fd;
    Event e; e.kind=Kind::hello;e.pid=getpid();e.flags=flags;
    if(!writeAll(fd,&e,sizeof(e))){close(fd);return -1;}
    return fd;
}
inline std::string request(const std::string& json) {
    int fd=connectSocket(true,250,true);if(fd<0)return "{\"error\":\"Axial service is not running\"}";
    const uint64_t deadline=now()+2000000000;
    std::string line=json+"\n",result;
    size_t sent=0;
    while(sent<line.size()&&now()<deadline) {
        auto n=send(fd,line.data()+sent,line.size()-sent,0);
        if(n>0){sent+=size_t(n);continue;}
        if(n<0&&errno==EINTR)continue;
        if(n<0&&(errno==EAGAIN||errno==EWOULDBLOCK)&&waitSocket(fd,POLLOUT,deadline))continue;
        break;
    }
    bool complete=false;
    if(sent==line.size())while(now()<deadline) {
        char buf[4096];auto n=recv(fd,buf,sizeof(buf),0);
        if(n>0){
            const auto* end=static_cast<const char*>(memchr(buf,'\n',size_t(n)));
            result.append(buf,end?size_t(end-buf):size_t(n));
            if(result.size()>1024*1024)break;
            if(end){complete=true;break;}
            continue;
        }
        if(n<0&&errno==EINTR)continue;
        if(n<0&&(errno==EAGAIN||errno==EWOULDBLOCK)&&waitSocket(fd,POLLIN,deadline))continue;
        break;
    }
    close(fd);
    return complete?result:"{\"error\":\"Service did not respond\"}";
}
}
