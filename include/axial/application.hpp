#pragma once
#include <libproc.h>
#include <string>
#include <unistd.h>

namespace sn {
struct ProcessIdentity {pid_t pid=0,parent=0;uid_t uid=0;uint64_t birth=0;std::string executable;};
inline ProcessIdentity processIdentity(pid_t pid) {
    proc_bsdinfo info{};char path[PROC_PIDPATHINFO_MAXSIZE]{};
    if(pid<=0||proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,sizeof(info))!=sizeof(info)||proc_pidpath(pid,path,sizeof(path))<=0)return {};
    return {pid,pid_t(info.pbi_ppid),info.pbi_uid,info.pbi_start_tvsec*1000000+info.pbi_start_tvusec,path};
}
inline std::string applicationRoot(const std::string& path) {
    auto end=path.find(".app/Contents/");return end==std::string::npos?std::string{}:path.substr(0,end+5);
}
template<class Lookup>
bool belongsToApplication(const ProcessIdentity& peer,const ProcessIdentity& foreground,Lookup lookup) {
    if(!peer.pid||!foreground.pid||peer.uid!=foreground.uid)return false;
    if(peer.pid==foreground.pid)return peer.birth==foreground.birth;
    const auto root=applicationRoot(foreground.executable);
    if(root.empty()||applicationRoot(peer.executable)!=root)return false;
    auto process=peer;
    for(int depth=0;depth<32&&process.parent>1;++depth){
        auto parent=lookup(process.parent);
        if(!parent.pid||parent.uid!=peer.uid||parent.pid==process.pid)return false;
        if(parent.pid==foreground.pid)return parent.birth==foreground.birth;
        process=parent;
    }
    return false;
}
}
