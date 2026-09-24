#import <Foundation/Foundation.h>
#include "support.hpp"
#define __cdecl
#include <navlib/navlib.h>
#include <dlfcn.h>
#include <sys/resource.h>
#include <algorithm>
#include <iostream>
#include <vector>

namespace {
navlib::matrix_t camera{};
std::atomic<uint64_t> latestInput{0};
std::vector<double> inputAge;
long get(navlib::param_t,navlib::property_t name,navlib::value_t* value) {
    if(!strcmp(name,"view.affine"))*value=camera;
    else if(!strcmp(name,"view.perspective")||!strcmp(name,"view.rotatable"))*value=true;
    else if(!strcmp(name,"view.target"))*value=navlib::point_t{0,0,0};
    else return navlib::make_result_code(0x201);
    return 0;
}
long set(navlib::param_t,navlib::property_t name,const navlib::value_t* value) {
    if(!strcmp(name,"view.affine")){camera=value->matrix;inputAge.push_back(double(sn::now()-latestInput)/1e6);}
    return 0;
}
double cpu() {rusage u{};getrusage(RUSAGE_SELF,&u);return u.ru_utime.tv_sec+u.ru_stime.tv_sec+(u.ru_utime.tv_usec+u.ru_stime.tv_usec)/1e6;}
double serviceCPU() {
    auto text=sn::request("{\"op\":\"status\"}");
    auto data=[NSData dataWithBytes:text.data() length:text.size()];
    NSDictionary* state=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(!state[@"cpuSeconds"])throw std::runtime_error("No service CPU measurement");
    return [state[@"cpuSeconds"] doubleValue];
}
}
int main(int argc,char** argv) {@autoreleasepool {try {
    if(argc<3)return 2;
    double seconds=argc>3?std::stod(argv[3]):5;if(seconds<=0)return 2;
    MockService service(argv[1],true);
    void* lib=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);if(!lib)throw std::runtime_error(dlerror());
    auto create=reinterpret_cast<decltype(&navlib::NlCreate)>(dlsym(lib,"NlCreate"));
    auto closeSession=reinterpret_cast<decltype(&navlib::NlClose)>(dlsym(lib,"NlClose"));
    if(!create||!closeSession)return 1;
    navlib::accessor_t properties[]={{"view.affine",get,set,0},{"view.perspective",get,nullptr,0},
        {"view.rotatable",get,nullptr,0},{"view.target",get,nullptr,0},{"motion",nullptr,set,0},{"transaction",nullptr,set,0}};
    camera.m00=camera.m11=camera.m22=camera.m33=1;camera.m23=10;
    navlib::nlCreateOptions_t options{sizeof(options),false,navlib::row_major_order};navlib::nlHandle_t handle;
    if(create(&handle,"Axial isolated CAD benchmark",properties,std::size(properties),&options))return 1;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,.2,false);
    int inject=sn::openEvents(sn::Flags::replay);if(inject<0)return 1;
    sn::Event event;event.device=1;event.vendor=0x046d;event.product=0xc627;event.kind=sn::Kind::added;
    sn::writeAll(inject,&event,sizeof(event));
    bool valid=true;
    for(const char* mode:{"idle","moving","stopped"}) {
        bool moving=!strcmp(mode,"moving");
        event.kind=sn::Kind::motion;event.axes={};if(moving)event.axes={100,0,0,30,0,0};
        auto run=[&](double duration) {
            std::atomic<bool> success=true;
            std::thread producer([&]{
                auto end=std::chrono::steady_clock::now()+std::chrono::duration<double>(duration);
                do {event.received=sn::now();latestInput=event.received;
                    if(!sn::writeAll(inject,&event,sizeof(event))){success=false;break;}
                    std::this_thread::sleep_until(moving?std::min(end,std::chrono::steady_clock::now()+std::chrono::duration<double>(.008)):end);
                }while(std::chrono::steady_clock::now()<end);
            });
            CFRunLoopRunInMode(kCFRunLoopDefaultMode,duration,false);
            producer.join();if(!success)throw std::runtime_error("Replay failed");
        };
        run(.5);inputAge.clear();double initialService=serviceCPU(),initialCPU=cpu();auto start=sn::now();run(seconds);
        double elapsed=double(sn::now()-start)/1e9,clientCPU=cpu()-initialCPU,serviceDelta=serviceCPU()-initialService;
        std::sort(inputAge.begin(),inputAge.end());double p95=inputAge.empty()?0:inputAge[size_t((inputAge.size()-1)*.95)];
        valid&=moving?!inputAge.empty():inputAge.empty();
        std::cout<<"{\"mode\":\""<<mode<<"\",\"seconds\":"<<elapsed<<",\"client_cpu_percent\":"<<clientCPU/elapsed*100
            <<",\"service_cpu_percent\":"<<serviceDelta/elapsed*100<<",\"frames\":"<<inputAge.size()<<",\"input_age_p95_ms\":"<<p95<<"}\n";
    }
    close(inject);closeSession(handle);return valid?0:1;
}catch(const std::exception& error){std::cerr<<error.what()<<"\n";return 1;}}}
