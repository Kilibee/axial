#include "axial/transport.hpp"
#include <filesystem>
#include <iostream>
#include <spawn.h>
#include <signal.h>
#include <sys/wait.h>
#include <thread>
extern char** environ;
int main(int argc,char** argv){
    if(argc!=2)return 2;
    char temporary[]="/tmp/axial-owner-XXXXXX";auto directory=mkdtemp(temporary);if(!directory)return 1;
    std::string path=std::string(directory)+"/events";
    setenv("AXIAL_SOCKET",path.c_str(),1);setenv("AXIAL_CONFIG",(std::string(directory)+"/settings.json").c_str(),1);
    int lifetime[2],identity[2];if(pipe(lifetime)||pipe(identity))return 1;
    pid_t owner=fork();if(owner<0)return 1;
    if(owner==0){
        close(lifetime[1]);close(identity[0]);
        fcntl(lifetime[0],F_SETFD,FD_CLOEXEC);fcntl(identity[1],F_SETFD,FD_CLOEXEC);
        pid_t service=-1;char* args[]={argv[1],const_cast<char*>("--mock"),const_cast<char*>("--app-owned"),nullptr};
        if(posix_spawn(&service,argv[1],nullptr,nullptr,args,environ))_exit(2);
        write(identity[1],&service,sizeof(service));close(identity[1]);
        char byte;read(lifetime[0],&byte,1);_exit(0); // Deliberately leave helper cleanup to its parent-exit watch.
    }
    close(lifetime[0]);close(identity[1]);pid_t service=-1;
    bool ok=read(identity[0],&service,sizeof(service))==sizeof(service);close(identity[0]);
    bool connected=false;
    for(int i=0;i<100&&!connected;++i){int fd=sn::connectSocket();connected=fd>=0;if(connected)close(fd);else std::this_thread::sleep_for(std::chrono::milliseconds(20));}
    ok&=connected;close(lifetime[1]);int status;waitpid(owner,&status,0);
    // The service unlinks the two sockets separately. Wait for both rather
    // than treating the instant between those operations as a cleanup failure.
    auto socketsGone=[&]{return !std::filesystem::exists(path)&&!std::filesystem::exists(path+".control");};
    for(int i=0;i<150&&!socketsGone();++i)std::this_thread::sleep_for(std::chrono::milliseconds(20));
    ok&=socketsGone();
    if(!ok&&service>0)kill(service,SIGTERM);
    std::filesystem::remove_all(directory);
    std::cout<<(ok?"PASS: native helper exits and releases sockets when its owning app exits\n":"FAIL: helper outlived its owning app\n");
    return ok?0:1;
}
