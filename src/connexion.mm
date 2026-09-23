#import <Foundation/Foundation.h>
#include "axial/connexion.h"
#include "axial/stream.hpp"
#include "axial/application_buttons.hpp"
#include <memory>
#include <cassert>
#include <string>

namespace {
dispatch_queue_t queue;
char queueKey;
std::unique_ptr<sn::Stream> stream;
ConnexionMessageHandler messageHandler=nullptr;
ConnexionDeviceHandler addedHandler=nullptr,removedHandler=nullptr;
struct Client {uint16_t id=0;uint32_t mask=0,buttons=0xffffffff,signature=0;uint16_t mode=0;std::string name;};
std::array<Client,16> clients;
std::array<sn::Event,16> devices;
uint16_t nextID=1;
bool installed=false;
uint64_t generation=0;
void stopStream() {
    if(stream){assert(queue);stream->stop();auto* retired=stream.release();dispatch_async(queue,^{delete retired;});}
    devices={};
}
void synchronized(dispatch_block_t block) {
    if(!queue||dispatch_get_specific(&queueKey)||(queue==dispatch_get_main_queue()&&pthread_main_np()))block();
    else dispatch_sync(queue,block);
}
void receive(void*,const sn::Event& e) {
    if(e.kind==sn::Kind::reset&&!e.device){
        const auto current=generation;const auto previous=devices;
        for(const auto& device:previous)if(device.device){
            auto reset=device;reset.kind=sn::Kind::reset;reset.axes={};reset.buttons=0;reset.flags=0;reset.received=e.received;
            receive(nullptr,reset);if(generation!=current)return;
        }
        if(e.flags&sn::Flags::disconnected){devices={};for(const auto& device:previous)if(device.device&&removedHandler){removedHandler(device.product);if(generation!=current)return;}}
        return;
    }
    if(e.kind==sn::Kind::added){
        auto slot=std::find_if(devices.begin(),devices.end(),[&](const auto& d){return d.device==e.device;});
        if(slot==devices.end())slot=std::find_if(devices.begin(),devices.end(),[](const auto& d){return !d.device;});
        if(slot!=devices.end())*slot=e;
        if(addedHandler)addedHandler(e.product);return;
    }
    if(e.kind==sn::Kind::removed){
        const auto current=generation;
        auto reset=e;reset.kind=sn::Kind::reset;reset.axes={};reset.buttons=0;receive(nullptr,reset);
        if(generation!=current)return;
        for(auto& d:devices)if(d.device==e.device)d={};
        if(removedHandler)removedHandler(e.product);return;
    }
    const auto current=generation;
    uint32_t previousButtons=0;
    for(auto& d:devices)if(d.device==e.device){previousButtons=d.buttons;if(e.kind==sn::Kind::buttons||e.kind==sn::Kind::reset)d.buttons=e.buttons;}
    for(const auto& c:clients)if(c.id&&messageHandler) {
        ConnexionDeviceState s{};s.version=0x6d33;s.client=c.id;s.address=uint16_t(e.device);s.time=e.received/1000;
        if(e.kind==sn::Kind::motion||e.kind==sn::Kind::reset) {
            if(c.mask&0x3f00){
            s.command=3;
            for(size_t i=0;i<6;++i)s.axis[i]=(c.mask&(0x100u<<i))?e.axes[i]:0;
            messageHandler(e.product,0x33645352,&s);
            if(generation!=current)return;
            }
        }
        if(e.kind==sn::Kind::buttons||e.kind==sn::Kind::reset) {
            // Application-event numbers are application-specific. Only enable
            // this contract for the public signature whose mapping is known.
            if(c.signature==0x626c6e64&&!c.buttons){
                uint32_t changed=previousButtons^e.buttons;
                for(unsigned i=0;i<32;++i)if(changed&(1u<<i)){
                    int button=sn::applicationButton(e.vendor,e.product,i);if(!button)continue;
                    s.command=11;s.value=button;s.appEventPressed=bool(e.buttons&(1u<<i));
                    messageHandler(e.product,0x33645352,&s);if(generation!=current)return;
                }
                continue;
            }
            if(!(c.mask&0xff)||!c.buttons)continue;
            s.command=2;s.buttons=e.buttons&c.buttons;s.buttons8=uint16_t(s.buttons);
            messageHandler(e.product,0x33645352,&s);
            if(generation!=current)return;
        }
    }
    if(e.flags&sn::Flags::disconnected){
        const auto previous=devices;devices={};
        for(const auto& device:previous)if(device.device&&removedHandler){removedHandler(device.product);if(generation!=current)return;}
    }
}
}
extern "C" {
int16_t SetConnexionHandlers(ConnexionMessageHandler m,ConnexionDeviceHandler a,ConnexionDeviceHandler r,bool separate) {
    static const bool mapped=[] {sn::keepCallbackCodeMapped(reinterpret_cast<const void*>(&SetConnexionHandlers));return true;}();(void)mapped;
    if(installed)CleanupConnexionHandlers();
    queue=separate?dispatch_queue_create("pro.jest.connexion",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_USER_INTERACTIVE,0)):dispatch_get_main_queue();
    dispatch_queue_set_specific(queue,&queueKey,&queueKey,nullptr);
    messageHandler=m;addedHandler=a;removedHandler=r;installed=true;++generation;return 0;
}
int16_t InstallConnexionHandlers(ConnexionMessageHandler m,ConnexionDeviceHandler a,ConnexionDeviceHandler r){return SetConnexionHandlers(m,a,r,false);}
void CleanupConnexionHandlers() {
    synchronized(^{++generation;stopStream();clients={};messageHandler=nullptr;addedHandler=nullptr;removedHandler=nullptr;installed=false;});
}
uint16_t RegisterConnexionClient(uint32_t signature,const uint8_t* name,uint16_t mode,uint32_t mask) {
    if(!installed||mode>1)return 0;
    __block uint16_t id=0;
    synchronized(^{for(auto& c:clients)if(!c.id){
            uint16_t candidate;
            do{candidate=nextID++;}while(!candidate||std::any_of(clients.begin(),clients.end(),[&](const auto& existing){return existing.id==candidate;}));
            id=candidate;
            c={id,mask,0xffffffff,signature,mode,name?std::string(reinterpret_cast<const char*>(name+1),name[0]):std::string{}};break;
        }
        if(id&&!stream){stream=std::make_unique<sn::Stream>(queue,receive,nullptr);stream->start();}
        else if(id&&addedHandler){auto current=generation;dispatch_async(queue,^{
            if(generation!=current)return;
            for(const auto& d:devices)if(d.device&&addedHandler){addedHandler(d.product);if(generation!=current)return;}
        });}
    });return id;
}
void UnregisterConnexionClient(uint16_t id){synchronized(^{for(auto& c:clients)if(c.id&&c.id==id){c={};++generation;}
    if(std::none_of(clients.begin(),clients.end(),[](const auto& c){return c.id!=0;}))stopStream();
});}
void SetConnexionClientMask(uint16_t id,uint32_t mask){synchronized(^{for(auto& c:clients)if(c.id==id)c.mask=mask;});}
void SetConnexionClientButtonMask(uint16_t id,uint32_t mask){synchronized(^{for(auto& c:clients)if(c.id==id)c.buttons=mask;});}
int16_t ConnexionClientControl(uint16_t id,uint32_t message,int32_t,int32_t* result) {
    if(!result)return -50;*result=0;
    __block int16_t error=-4;
    synchronized(^{bool found=id==0;for(const auto& c:clients)found|=c.id==id;if(!found){error=-50;return;}
        if(message==0x33646964){error=0;for(const auto& d:devices)if(d.device){*result=int32_t(uint32_t(d.vendor)<<16|d.product);break;}}
    });
    if(error==-4&&getenv("AXIAL_COMPAT_DEBUG"))fprintf(stderr,"Axial: unsupported Connexion control %08x (client %u)\n",message,id);
    return error;
}
int16_t ConnexionControl(uint32_t message,int32_t param,int32_t* result){return ConnexionClientControl(0,message,param,result);}
}
