#include "support.hpp"
#include "axial/connexion.h"
#include <dlfcn.h>
#include <atomic>
#include <vector>
#include <iostream>
#include <iomanip>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <fstream>
#include <pthread/qos.h>

namespace {
std::vector<uint64_t> samples;
std::atomic<size_t> count=0;
std::atomic<bool> measuring=false;
std::atomic<uint64_t> buttonCallbacks=0;
void message(uint32_t,uint32_t,void* value){
    uint64_t end=sn::now();auto state=static_cast<ConnexionDeviceState*>(value);
    if(state->address!=1)return; // Focus-reset notifications are not injected motion samples.
    if(state->command==2){++buttonCallbacks;return;}
    if(state->command!=3||!measuring.load(std::memory_order_relaxed)||!state->time)return;
    size_t i=count.load(std::memory_order_relaxed);
    if(i<samples.size()){samples[i]=end-state->time*1000;count.store(i+1,std::memory_order_release);}
}
double percentile(const std::vector<uint64_t>& v,double p){return v.empty()?0:double(v[std::min(v.size()-1,size_t(std::ceil(p*v.size())-1))])/1000;}
void summary(const char* name,std::vector<uint64_t> data,size_t sent,double cpu){
    std::sort(data.begin(),data.end());
    std::cout<<"{\"name\":\""<<name<<"\",\"unit\":\"us\",\"sent\":"<<sent<<",\"received\":"<<data.size()<<",\"p50\":"<<percentile(data,.5)<<",\"p95\":"<<percentile(data,.95)<<",\"p99\":"<<percentile(data,.99)<<",\"p999\":"<<percentile(data,.999)<<",\"max\":"<<percentile(data,1)<<",\"cpu_seconds\":"<<cpu<<",\"over_1ms\":"<<std::count_if(data.begin(),data.end(),[](uint64_t x){return x>1000000;})<<"}\n";
}
double cpuTime(){rusage usage{};getrusage(RUSAGE_SELF,&usage);return usage.ru_utime.tv_sec+usage.ru_stime.tv_sec+(usage.ru_utime.tv_usec+usage.ru_stime.tv_usec)/1e6;}
}
int main(int argc,char** argv){
    // Model a HID producer at input priority. CPU burners below explicitly use
    // ordinary application priority, independent of this thread's inheritance.
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE,0);
    if(argc<3){std::cerr<<"usage: axial-bench service client-dylib [seconds=120] [rate=1000] [warmup=10] [--contention]\n";return 2;}
    double seconds=argc>3?std::stod(argv[3]):120;int rate=argc>4?std::stoi(argv[4]):1000;double warmup=argc>5?std::stod(argv[5]):10;
    if(seconds<=0||seconds>3600||rate<1||rate>10000||warmup<0)return 2;
    bool contention=argc>6&&std::string(argv[6])=="--contention";
    bool diagnose=argc>7&&std::string(argv[7])=="--diagnose";
    std::cout<<std::fixed<<std::setprecision(3);
    char cpuName[128]="unknown",osVersion[64]="unknown";size_t size=sizeof(cpuName);sysctlbyname("machdep.cpu.brand_string",cpuName,&size,nullptr,0);size=sizeof(osVersion);sysctlbyname("kern.osproductversion",osVersion,&size,nullptr,0);
#if defined(__arm64__)
    const char* architecture="arm64";
#else
    const char* architecture="x86_64";
#endif
    std::cout<<"{\"environment\":{\"cpu\":\""<<cpuName<<"\",\"macos\":\""<<osVersion<<"\",\"architecture\":\""<<architecture<<"\",\"contention\":"<<(contention?"true":"false")<<",\"nice\":"<<getpriority(PRIO_PROCESS,0)<<",\"logical_cpus\":"<<std::thread::hardware_concurrency()<<"}}\n";
    // Isolate parser/filter work, measuring each invocation with a monotonic clock.
    std::vector<uint64_t> parser(200000);sn::Decoder decoder;sn::Settings settings;sn::Event event;
    uint8_t packet[13]={1,0x34,0,0xee,0xff,0x19,0,0,0,0,0,0x30,0};uint64_t checksum=0;
    for(auto& sample:parser){packet[1]++;uint64_t begin=sn::now();decoder.decode(packet,begin,event);event=sn::filter(event,settings);sample=sn::now()-begin;checksum+=uint16_t(event.axes[0]);}
    summary("decode_filter",parser,parser.size(),0);std::cerr<<"checksum="<<checksum<<"\n";
    sn::EventQueue<256> pending;std::vector<uint64_t> enqueueSamples(parser.size());
    for(auto& sample:enqueueSamples){packet[1]++;uint64_t begin=sn::now();decoder.decode(packet,begin,event);event=sn::filter(event,settings);pending.push(event);asm volatile("" : : "g"(&pending) : "memory");pending.pop();sample=sn::now()-begin;}
    summary("decode_filter_enqueue",enqueueSamples,enqueueSamples.size(),0);
    sn::Decoder enterprise;enterprise.state.vendor=0x256f;enterprise.state.product=0xc633;
    uint8_t chord[13]={0x1c,25,0,26,0,77,0,103,0,175,0,176,0};
    uint8_t released[13]={0x1c};std::vector<uint64_t> enterpriseSamples(parser.size());
    for(auto& sample:enterpriseSamples){
        // HID bytes arrive at runtime: prevent constant-folding the usage map.
        asm volatile("" : "+m"(chord), "+m"(released) : : "memory");
        uint64_t begin=sn::now();enterprise.decode(chord,begin,event);asm volatile("" : : "g"(&event) : "memory");enterprise.decode(released,begin,event);asm volatile("" : : "g"(&event) : "memory");sample=sn::now()-begin;
    }
    summary("enterprise_six_key_press_release",enterpriseSamples,enterpriseSamples.size(),0);
    MockService service(argv[1],true);
    void* lib=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);if(!lib){std::cerr<<dlerror();return 1;}
    auto install=reinterpret_cast<decltype(&SetConnexionHandlers)>(dlsym(lib,"SetConnexionHandlers"));
    auto reg=reinterpret_cast<decltype(&RegisterConnexionClient)>(dlsym(lib,"RegisterConnexionClient"));
    auto cleanup=reinterpret_cast<decltype(&CleanupConnexionHandlers)>(dlsym(lib,"CleanupConnexionHandlers"));
    if(!install||!reg||!cleanup||install(message,nullptr,nullptr,true)!=0||!reg(0,nullptr,1,0x3fff))return 1;
    int inject=sn::openEvents(sn::Flags::replay);if(inject<0)return 1;
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    sn::Event e;e.kind=sn::Kind::added;e.device=1;e.vendor=0x046d;e.product=0xc627;sn::writeAll(inject,&e,sizeof(e));
    std::atomic<bool> running=true;std::vector<std::thread> workers;
    if(contention){
        size_t threads=std::max(1u,std::thread::hardware_concurrency()-1);
        for(size_t i=0;i<threads;++i)workers.emplace_back([&]{pthread_set_qos_class_self_np(QOS_CLASS_DEFAULT,0);volatile uint64_t x=1;while(running.load(std::memory_order_relaxed))for(int j=0;j<10000;++j)x=x*6364136223846793005ULL+1;});
        workers.emplace_back([&]{pthread_set_qos_class_self_np(QOS_CLASS_UTILITY,0);while(running){sn::request("{\"op\":\"status\"}");std::this_thread::sleep_for(std::chrono::milliseconds(100));}});
    }
    samples.resize(size_t(seconds*rate*1.2)+1000);
    std::vector<uint64_t> producerLateness(size_t(seconds*rate));
    std::vector<uint64_t> toService(diagnose?samples.size():0),fromService(diagnose?samples.size():0);
    size_t diagnosticCount=0;int diagnosticFD=-1;std::thread diagnosticReader;
    if(diagnose){
        diagnosticFD=sn::openEvents(sn::Flags::monitor);
        diagnosticReader=std::thread([&]{pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE,0);sn::Event event;
            while(sn::readAll(diagnosticFD,&event,sizeof(event)))if(event.kind==sn::Kind::motion&&event.device==1&&measuring.load()&&diagnosticCount<toService.size()){
                toService[diagnosticCount]=event.decoded-event.received;fromService[diagnosticCount]=sn::now()-event.decoded;++diagnosticCount;
            }
        });
    }
    auto run=[&](double duration){
        size_t total=size_t(duration*rate);auto start=std::chrono::steady_clock::now();
        for(size_t i=0;i<total;++i){
            auto scheduled=start+std::chrono::nanoseconds(uint64_t(i)*(1000000000/rate));
            std::this_thread::sleep_until(scheduled);
            if(measuring.load(std::memory_order_relaxed)&&i<producerLateness.size())producerLateness[i]=std::max<int64_t>(0,std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-scheduled).count());
            e.kind=sn::Kind::motion;e.sequence=i;e.axes={int16_t((i%349)+1),-50,20,0,0,30};e.received=sn::now();
            if(!sn::writeAll(inject,&e,sizeof(e)))return size_t(0);
            if(i%100==0){auto button=e;button.kind=sn::Kind::buttons;button.buttons=(i/100)%2;sn::writeAll(inject,&button,sizeof(button));}
        }return total;
    };
    run(warmup);std::this_thread::sleep_for(std::chrono::milliseconds(50));
    std::string initialStatus=sn::request("{\"op\":\"status\"}");
    count=0;buttonCallbacks=0;measuring=true;
    double cpu=cpuTime();size_t sent=run(seconds);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));measuring=false;cleanup();
    cpu=cpuTime()-cpu;running=false;for(auto& worker:workers)worker.join();
    size_t received=count.load();samples.resize(std::min(received,samples.size()));
    if(diagnose){shutdown(diagnosticFD,SHUT_RDWR);diagnosticReader.join();close(diagnosticFD);toService.resize(diagnosticCount);fromService.resize(diagnosticCount);summary("injection_to_service",toService,sent,0);summary("service_to_monitor",fromService,sent,0);}
    summary(contention?"service_to_framework_contended":"service_to_framework",samples,sent,cpu);
    summary("producer_schedule_lateness",producerLateness,sent,0);
    std::cout<<"{\"rate\":"<<rate<<",\"seconds\":"<<seconds<<",\"warmup\":"<<warmup<<",\"button_callbacks\":"<<buttonCallbacks.load()<<",\"service_initial\":"<<initialStatus<<",\"service_status\":"<<sn::request("{\"op\":\"status\"}")<<"}\n";
    close(inject);
    std::sort(samples.begin(),samples.end());
    std::sort(parser.begin(),parser.end());
    std::sort(enqueueSamples.begin(),enqueueSamples.end());
    std::sort(enterpriseSamples.begin(),enterpriseSamples.end());
    bool budget=!samples.empty()&&percentile(samples,.99)<=(contention?4000:1000)&&percentile(samples,.999)<=(contention?8000:2000);
    // Missing callbacks are a separate failure; latency statistics alone can hide loss.
    return budget&&received==sent&&buttonCallbacks.load()==size_t(std::ceil(double(sent)/100))&&percentile(enqueueSamples,.99)<=100&&percentile(enterpriseSamples,.99)<=100?0:1;
}
