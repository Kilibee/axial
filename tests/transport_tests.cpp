#include "axial/transport.hpp"
#include <chrono>
#include <filesystem>
#include <iostream>
#include <thread>
#include <functional>
#include <vector>
#include <stdexcept>
#define CHECK(x) do {if(!(x))throw std::runtime_error(#x);} while(0)
using namespace std::chrono_literals;
struct Listener {
    int fd=-1;
    std::string directory;
    Listener(){
        char path[]="/tmp/axial-transport-XXXXXX";auto p=mkdtemp(path);CHECK(p);directory=p;
        setenv("AXIAL_SOCKET",(directory+"/events").c_str(),1);
        fd=socket(AF_UNIX,SOCK_STREAM,0);CHECK(fd>=0);sn::socketOptions(fd);
        sockaddr_un address{};address.sun_family=AF_UNIX;auto name=sn::socketPath(true);
        memcpy(address.sun_path,name.c_str(),name.size()+1);
        CHECK(bind(fd,reinterpret_cast<sockaddr*>(&address),sizeof(address))==0);CHECK(listen(fd,1)==0);
    }
    ~Listener(){close(fd);std::filesystem::remove_all(directory);}
};
std::pair<std::string,double> reply(std::function<void(int)> writer){
    Listener listener;
    std::thread server([&]{int fd=accept(listener.fd,nullptr,nullptr);sn::socketOptions(fd);char data[1024];recv(fd,data,sizeof(data),0);writer(fd);close(fd);});
    auto start=sn::now();auto result=sn::request("{}");double seconds=double(sn::now()-start)/1e9;
    server.join();return {result,seconds};
}
int main(){try{
    auto [valid,elapsed]=reply([](int fd){sn::writeAll(fd,"{\"ok\":",6);std::this_thread::sleep_for(5ms);sn::writeAll(fd,"true}\ntrailing",14);});
    CHECK(valid=="{\"ok\":true}");CHECK(elapsed<1);
    CHECK(reply([](int fd){sn::writeAll(fd,"{\"ok\":true}",11);}).first.find("error")!=std::string::npos);
    CHECK(reply([](int fd){std::string huge(1024*1024+1,'x');huge+='\n';sn::writeAll(fd,huge.data(),huge.size());}).first.find("error")!=std::string::npos);
    auto [trickled,duration]=reply([](int fd){for(int i=0;i<30;++i){if(!sn::writeAll(fd," ",1))break;std::this_thread::sleep_for(100ms);}});
    CHECK(trickled.find("error")!=std::string::npos);CHECK(duration>=1.8&&duration<2.7);
    Listener listener;std::vector<int> clients;
    for(int i=0;i<16;++i){auto begin=sn::now();int fd=sn::connectSocket(true,0,true);CHECK(sn::now()-begin<100000000);if(fd<0)break;clients.push_back(fd);}
    CHECK(clients.size()<16);auto begin=sn::now();CHECK(sn::connectSocket(true,100)<0);CHECK(sn::now()-begin<400000000);
    for(int fd:clients)close(fd);
    std::cout<<"PASS: fragmented replies, framing, size limit, absolute deadline and full listener backlog\n";
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
