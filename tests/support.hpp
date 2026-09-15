#pragma once
#include "axial/transport.hpp"
#include <spawn.h>
#include <signal.h>
#include <sys/wait.h>
#include <cstdio>
#include <chrono>
#include <thread>
#include <stdexcept>
#include <filesystem>
extern char** environ;
struct MockService {
    pid_t pid=-1;std::string directory;
    explicit MockService(const char* executable,bool appOwned=false) {
        char path[]="/tmp/axial-tests-XXXXXX";char* dir=mkdtemp(path);
        if(!dir)throw std::runtime_error("mkdtemp failed");directory=dir;
        setenv("AXIAL_SOCKET",(directory+"/events").c_str(),1);
        setenv("AXIAL_CONFIG",(directory+"/settings.json").c_str(),1);
        char* args[]={const_cast<char*>(executable),const_cast<char*>("--mock"),appOwned?const_cast<char*>("--app-owned"):nullptr,nullptr};
        int rc=posix_spawn(&pid,executable,nullptr,nullptr,args,environ);
        if(rc)throw std::runtime_error("Cannot launch mock service");
        for(int i=0;i<500;++i){int fd=sn::connectSocket();if(fd>=0){close(fd);return;}std::this_thread::sleep_for(std::chrono::milliseconds(10));}
        kill(pid,SIGTERM);waitpid(pid,nullptr,0);pid=-1;throw std::runtime_error("Mock service did not start");
    }
    ~MockService(){if(pid>0){kill(pid,SIGTERM);waitpid(pid,nullptr,0);}std::filesystem::remove_all(directory);}
};
