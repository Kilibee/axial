#import <AppKit/AppKit.h>
#import <CoreVideo/CoreVideo.h>
#include <cerrno>
#define __cdecl
#include <navlib/navlib.h>
#include "axial/navigation.hpp"
#include "axial/stream.hpp"
#include <map>
#include <mutex>
#include <atomic>
#include <memory>
#include <vector>
#include <string>

using namespace navlib;
namespace {
struct Slot { std::string name;fnGetProperty_t get=nullptr;fnSetProperty_t set=nullptr;param_t param=0;value_t cached;bool hasValue=false;std::string text; };
struct DeviceBindings {uint32_t id=0,buttons=0;uint16_t vendor=0,product=0;std::array<std::string,32> commands;};
struct Session;
std::mutex registryMutex;
std::map<nlHandle_t,std::shared_ptr<Session>> sessions;
std::atomic<nlHandle_t> activeHandle{0};
nlHandle_t nextHandle=1;
long failure(unsigned code){return make_result_code(code);}
bool finite(sn::Vec v){return std::isfinite(v.x)&&std::isfinite(v.y)&&std::isfinite(v.z);}
bool validBox(const box_t& b){
    return finite({b.min.x,b.min.y,b.min.z})&&finite({b.max.x,b.max.y,b.max.z})&&
        b.max.x>=b.min.x&&b.max.y>=b.min.y&&b.max.z>=b.min.z;
}
std::shared_ptr<Session> find(nlHandle_t h){std::lock_guard lock(registryMutex);auto it=sessions.find(h);return it==sessions.end()?nullptr:it->second;}
struct Session {
    nlHandle_t handle=0;
    std::string app;
    dispatch_queue_t queue;
    std::map<std::string,Slot,std::less<>> properties;
    std::unique_ptr<sn::Stream> stream;
    dispatch_source_t frames=nullptr,fallbackFrames=nullptr;
    CVDisplayLinkRef display=nullptr;
    bool active=true,focused=true,moving=false,rowMajor=false,closed=false,clientTiming=false;
    bool bindingsPending=false,bindingsDirty=false;
    std::array<DeviceBindings,16> devices{};
    uint64_t lastFrame=0,lastInput=0;
    double clientFrame=0;
    sn::Event input;
    std::string commandRequest;
    dispatch_source_t refresh=nullptr;
    Slot* slot(const char* name){auto it=properties.find(name);return it==properties.end()?nullptr:&it->second;}
    bool get(const char* name,value_t& value) {
        if(closed)return false;
        Slot* s=slot(name);if(!s)return false;
        if(s->get){if(s->get(s->param,s->name.c_str(),&value)==0)return true;if(closed)return false;}
        if(s->hasValue){value=s->cached;return true;}return false;
    }
    bool set(const char* name,const value_t& value){if(closed)return false;Slot* s=slot(name);if(!s||!s->set)return false;return s->set(s->param,s->name.c_str(),&value)==0;}
    void sync(dispatch_block_t block){if(dispatch_get_specific(this)||(queue==dispatch_get_main_queue()&&pthread_main_np()))block();else dispatch_sync(queue,block);}
    void updateFrameClock(){
        bool run=moving&&active&&focused&&!closed&&!clientTiming;
        bool fallback=run;
        if(display){
            if(run&&!CVDisplayLinkIsRunning(display))CVDisplayLinkStart(display);
            else if(!run&&CVDisplayLinkIsRunning(display))CVDisplayLinkStop(display);
            fallback=run&&!CVDisplayLinkIsRunning(display);
        }
        if(fallbackFrames)dispatch_source_set_timer(fallbackFrames,fallback?DISPATCH_TIME_NOW:DISPATCH_TIME_FOREVER,NSEC_PER_SEC/120,500000);
    }
    void stopMotion(){input.axes={};if(moving){moving=false;updateFrameClock();set("motion",value_t(false));}lastFrame=0;clientFrame=0;}
    void fit(){
        value_t bounds,affine;
        if(!get("model.extents",bounds)||bounds.type!=box_type||!get("view.affine",affine)||affine.type!=matrix_type||closed)return;
        const auto& b=bounds.box;if(!validBox(b))return;
        for(int i=0;i<16;++i)if(!std::isfinite(affine.matrix[i]))return;
        sn::Vec centre{b.min.x/2+b.max.x/2,b.min.y/2+b.max.y/2,b.min.z/2+b.max.z/2};
        double radius=std::max(1e-6,sn::length(sn::Vec{b.max.x-b.min.x,b.max.y-b.min.y,b.max.z-b.min.z})/2);
        if(!std::isfinite(radius))return;
        auto index=[&](int i){return rowMajor?(i%4)*4+i/4:i;};
        sn::Vec back{affine.matrix[index(8)],affine.matrix[index(9)],affine.matrix[index(10)]};
        double n=sn::length(back);if(!std::isfinite(n)||n<1e-12)return;back=back*(1/n);
        value_t v;double fov=0.7853981633974483;if(get("view.fov",v)&&v.type==double_type&&std::isfinite(v.d))fov=std::clamp(v.d,0.05,3.0);
        sn::Vec position=centre+back*(radius/std::sin(fov/2)*1.05);
        if(!finite(position))return;
        affine.matrix[index(12)]=position.x;affine.matrix[index(13)]=position.y;affine.matrix[index(14)]=position.z;
        set("transaction",value_t(long(1)));if(closed)return;set("view.affine",affine);if(closed)return;
        value_t extents;if(get("view.extents",extents)&&extents.type==box_type&&validBox(extents.box)){
            double height=extents.box.max.y-extents.box.min.y;double aspect=height>0?(extents.box.max.x-extents.box.min.x)/height:1;
            aspect=std::max(.01,aspect);extents.box.min.x=-radius*std::max(1.,aspect);extents.box.max.x=-extents.box.min.x;extents.box.min.y=-radius*std::max(1.,1/aspect);extents.box.max.y=-extents.box.min.y;if(validBox(extents.box))set("view.extents",extents);
        }
        if(closed)return;set("pivot.position",value_t(point_t{centre.x,centre.y,centre.z}));if(closed)return;set("transaction",value_t(long(0)));
    }
    void frame(double explicitDT=0) {
        if(closed||!active||!focused||!moving)return;
        if(activeHandle.load(std::memory_order_relaxed)!=handle){stopMotion();return;}
        uint64_t time=sn::now();
        if(lastInput&&time-lastInput>250000000){stopMotion();return;}
        double dt=explicitDT>0?explicitDT:(lastFrame?double(time-lastFrame)/1e9:1.0/120.0);
        lastFrame=time;
        value_t affine;
        if(!get("view.affine",affine)||affine.type!=matrix_type||closed)return;
        double m[16];for(int i=0;i<16;++i)m[i]=affine.matrix[rowMajor?(i%4)*4+i/4:i];
        for(double x:m)if(!std::isfinite(x))return;
        sn::Camera c{{m[0],m[1],m[2]},{m[4],m[5],m[6]},{m[8],m[9],m[10]},{m[12],m[13],m[14]}};
        bool perspective=true,rotatable=true;value_t v;
        if(get("view.perspective",v)&&v.type==bool_type)perspective=v.b;
        if(get("view.rotatable",v)&&v.type==bool_type)rotatable=v.b;
        if(closed)return;
        if(get("view.constructionPlane",v)&&v.type==plane_type&&!perspective){
            sn::Vec normal{v.plane.n.x,v.plane.n.y,v.plane.n.z};
            double n=sn::length(normal);if(n>1e-12&&std::abs(sn::dot(c.back,normal)/n)>0.9999)rotatable=false;
        }
        sn::Vec pivot{};bool supplied=false;
        if(get("pivot.position",v)&&v.type==point_type){pivot={v.point.x,v.point.y,v.point.z};supplied=true;}
        if(!supplied&&get("view.target",v)&&v.type==point_type){pivot={v.point.x,v.point.y,v.point.z};supplied=true;}
        if(!supplied&&get("model.extents",v)&&v.type==box_type)pivot={(v.box.min.x+v.box.max.x)/2,(v.box.min.y+v.box.max.y)/2,(v.box.min.z+v.box.max.z)/2};
        if(!finite(pivot))return;
        double scale=std::max(1e-3,sn::length(c.position-pivot));
        if(get("view.focusDistance",v)&&v.type==double_type&&std::isfinite(v.d)&&v.d>0)scale=v.d;
        value_t extents;bool hasExtents=!perspective&&get("view.extents",extents)&&extents.type==box_type;
        if(hasExtents&&!validBox(extents.box))return;
        if(hasExtents)scale=std::max(1e-3,extents.box.max.y-extents.box.min.y);
        if(closed||!std::isfinite(scale))return;
        sn::navigate(c,pivot,input.axes,dt,scale,input.flags&sn::Flags::orbit,rotatable,perspective);
        double next[16]={c.right.x,c.right.y,c.right.z,0,c.up.x,c.up.y,c.up.z,0,c.back.x,c.back.y,c.back.z,0,c.position.x,c.position.y,c.position.z,1};
        for(double x:next)if(!std::isfinite(x))return;
        for(int i=0;i<16;++i)affine.matrix[rowMajor?(i%4)*4+i/4:i]=next[i];
        set("transaction",value_t(long(1)));if(closed)return;
        set("view.affine",affine);if(closed)return;
        if(hasExtents&&input.axes[1]){
            double factor=std::exp(std::clamp(input.axes[1]/350.0*dt*2.0,-1.0,1.0));
            double cx=(extents.box.min.x+extents.box.max.x)/2,cy=(extents.box.min.y+extents.box.max.y)/2;
            extents.box.min.x=cx+(extents.box.min.x-cx)*factor;extents.box.max.x=cx+(extents.box.max.x-cx)*factor;
            extents.box.min.y=cy+(extents.box.min.y-cy)*factor;extents.box.max.y=cy+(extents.box.max.y-cy)*factor;
            if(validBox(extents.box))set("view.extents",extents);if(closed)return;
        }
        set("transaction",value_t(long(0)));
    }
    void receive(const sn::Event& e){
        if(closed)return;
        if(e.kind==sn::Kind::added){
            if(!e.device)return;
            auto found=std::find_if(devices.begin(),devices.end(),[&](const auto& d){return d.id==e.device;});
            if(found==devices.end())for(auto& d:devices)if(!d.id){d.id=e.device;d.vendor=e.vendor;d.product=e.product;break;}
            loadBindings();if(!commandRequest.empty()){auto request=commandRequest;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{sn::request(request);});}return;
        }
        if(e.kind==sn::Kind::removed||e.kind==sn::Kind::reset){
            if(e.flags&sn::Flags::disconnected)devices={};
            else for(auto& d:devices)if(!e.device||d.id==e.device){if(e.kind==sn::Kind::removed)d={};else d.buttons=0;}
            stopMotion();value_t release;release.type=string_type;release.string={const_cast<char*>(""),1};set("commands.activeCommand",release);if(!closed)loadBindings();return;
        }
        if(!active||!focused||activeHandle.load(std::memory_order_relaxed)!=handle)return;
        if(e.kind==sn::Kind::command&&(e.flags&0x10000)){fit();return;}
        if(e.kind==sn::Kind::motion){
            input=e;lastInput=sn::now();
            bool nonzero=std::any_of(e.axes.begin(),e.axes.end(),[](int x){return x!=0;});
            if(nonzero&&!moving){moving=true;lastFrame=sn::now();set("motion",value_t(true));
                if(!clientTiming)frame(1.0/120);updateFrameClock();}
            else if(!nonzero&&moving)stopMotion();
        } else if(e.kind==sn::Kind::buttons){
            auto found=std::find_if(devices.begin(),devices.end(),[&](const auto& d){return d.id==e.device;});
            if(found==devices.end())return;
            uint32_t changed=e.buttons^found->buttons;found->buttons=e.buttons;
            for(int i=0;i<32&&!closed;++i)if((changed&(1u<<i))&&!found->commands[i].empty()){
                // Copy before the client callback, which may reenter and reset the session.
                std::string text=(e.buttons&(1u<<i))?found->commands[i]:"";
                value_t command;command.type=string_type;command.string={text.data(),text.size()+1};set("commands.activeCommand",command);
            }
        }
    }
    void loadBindings(){
        if(closed)return;
        if(bindingsPending){bindingsDirty=true;return;}
        auto self=find(handle);if(!self)return;
        bindingsPending=true;
        auto snapshot=devices;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool {
            std::string data=sn::request("{\"op\":\"getConfig\"}");
            id doc=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:data.data() length:data.size()] options:0 error:nil];
            NSString* bundle=NSBundle.mainBundle.bundleIdentifier?:@"";
            id profiles=[doc isKindOfClass:NSDictionary.class]?doc[@"profiles"]:nil;
            if(![profiles isKindOfClass:NSDictionary.class])profiles=nil;
            auto resolved=snapshot;
            for(auto& device:resolved){
                device.commands={};if(!device.id)continue;
                NSString* suffix=[NSString stringWithFormat:@"@%04x:%04x",device.vendor,device.product];
                NSDictionary* profile=profiles[[bundle stringByAppendingString:suffix]]?:profiles[[@"*" stringByAppendingString:suffix]]?:profiles[bundle]?:profiles[@"*"];
                NSArray* buttons=[profile isKindOfClass:NSDictionary.class]?profile[@"buttons"]:nil;
                if([buttons isKindOfClass:NSArray.class])for(NSUInteger i=0;i<MIN(buttons.count,32);++i){id b=buttons[i];id command=[b isKindOfClass:NSDictionary.class]?b[@"command"]:nil;if([command isKindOfClass:NSString.class])device.commands[i]=[command UTF8String];}
            }
            dispatch_async(self->queue,^{
                if(self->closed)return;
                self->bindingsPending=false;
                if(profiles)for(auto& device:self->devices)for(const auto& value:resolved)if(device.id&&device.id==value.id)device.commands=value.commands;
                if(self->bindingsDirty){self->bindingsDirty=false;self->loadBindings();}
            });
        }});
    }
    void start(){
        stream=std::make_unique<sn::Stream>(queue,[](void* ctx,const sn::Event& e){auto* s=static_cast<Session*>(ctx);if(!s->closed)s->receive(e);},this);stream->start();
        frames=dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD,0,0,queue);
        Session* self=this;
        dispatch_source_set_event_handler(frames,^{if(!self->closed&&!self->clientTiming)self->frame();});dispatch_resume(frames);
        if(CVDisplayLinkCreateWithActiveCGDisplays(&display)==kCVReturnSuccess){
            CVDisplayLinkSetOutputCallback(display,[](CVDisplayLinkRef,const CVTimeStamp*,const CVTimeStamp*,CVOptionFlags,CVOptionFlags*,void* ctx)->CVReturn{
                auto s=static_cast<Session*>(ctx);dispatch_source_merge_data(s->frames,1);return kCVReturnSuccess;
            },this);
        }
        {
            fallbackFrames=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
            dispatch_source_set_event_handler(fallbackFrames,^{if(!self->closed&&!self->clientTiming)self->frame();});
            dispatch_source_set_timer(fallbackFrames,DISPATCH_TIME_FOREVER,NSEC_PER_SEC/120,500000);dispatch_resume(fallbackFrames);
        }
        refresh=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
        dispatch_source_set_timer(refresh,DISPATCH_TIME_NOW,2*NSEC_PER_SEC,200*NSEC_PER_MSEC);
        dispatch_source_set_event_handler(refresh,^{auto s=find(self->handle);if(s)s->loadBindings();});dispatch_resume(refresh);
    }
    void close(){if(closed)return;closed=true;stream->stop();if(display){CVDisplayLinkStop(display);CVDisplayLinkRelease(display);display=nullptr;}
        if(frames){dispatch_source_cancel(frames);frames=nullptr;}if(refresh){dispatch_source_cancel(refresh);refresh=nullptr;}
        if(fallbackFrames){dispatch_source_cancel(fallbackFrames);fallbackFrames=nullptr;}
        dispatch_queue_set_specific(queue,this,nullptr,nullptr);
    }
};
void publishCommands(Session& s,const SiActionNodeEx_t* root){
    NSMutableArray* commands=[NSMutableArray array];
    std::vector<const SiActionNodeEx_t*> todo; if(root)todo.push_back(root);
    size_t visited=0;
    while(!todo.empty()&&visited++<4096){auto n=todo.back();todo.pop_back();
        if(n->size<sizeof(SiActionNodeEx_t))break;
        if(n->type==SI_ACTION_NODE&&n->id)[commands addObject:@{@"id":@(n->id),@"label":n->label?@(n->label):@(n->id)}];
        if(n->next)todo.push_back(n->next);if(n->children)todo.push_back(n->children);
    }
    NSString* bundle=NSBundle.mainBundle.bundleIdentifier?:@(s.app.c_str());
    NSData* bytes=[NSJSONSerialization dataWithJSONObject:@{@"op":@"commands",@"app":bundle,@"commands":commands} options:0 error:nil];
    std::string request(static_cast<const char*>(bytes.bytes),bytes.length);
    s.commandRequest=request;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{sn::request(request);});
}
}
extern "C" {
long NlCreate(nlHandle_t* out,const char* app,const accessor_t accessors[],size_t count,const nlCreateOptions_t* options){
    static const bool mapped=[] {sn::keepCallbackCodeMapped(reinterpret_cast<const void*>(&NlCreate));return true;}();(void)mapped;
    if(!out)return failure(EINVAL);*out=0;
    if(!app||(!accessors&&count)||count>256||(options&&options->size<sizeof(nlCreateOptions_t)))return failure(EINVAL);
    auto s=std::make_shared<Session>();s->app=app;
    s->rowMajor=options&&(options->options&row_major_order);
    s->queue=options&&options->bMultiThreaded?dispatch_queue_create("pro.jest.navlib",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_USER_INTERACTIVE,0)):dispatch_get_main_queue();
    for(size_t i=0;i<count;++i){if(!accessors[i].name)return failure(EINVAL);Slot slot;slot.name=accessors[i].name;slot.get=accessors[i].fnGet;slot.set=accessors[i].fnSet;slot.param=accessors[i].param;s->properties.emplace(slot.name,std::move(slot));}
    dispatch_queue_set_specific(s->queue,s.get(),s.get(),nullptr);
    {std::lock_guard lock(registryMutex);s->handle=nextHandle++;sessions.emplace(s->handle,s);}
    *out=s->handle;activeHandle=s->handle;s->sync(^{s->start();});return 0;
}
long NlClose(nlHandle_t handle){
    auto s=find(handle);if(!s)return failure(EINVAL);
    nlHandle_t expected=handle;activeHandle.compare_exchange_strong(expected,0);
    s->sync(^{s->stopMotion();s->close();});
    {std::lock_guard lock(registryMutex);sessions.erase(handle);}
    // Preserve lifetime until any currently executing callback has unwound.
    dispatch_async(s->queue,^{(void)s;});return 0;
}
propertyType_t NlGetType(property_t name){
    if(!name)return unknown_type;
    for(const auto& p:navlib::propertyDescription)if(strcmp(p.name,name)==0)return p.type;
    return unknown_type;
}
long NlReadValue(nlHandle_t handle,property_t name,value_t* out){
    auto s=find(handle);if(!s||!name||!out)return failure(EINVAL);
    __block long result=0;
    s->sync(^{
        if(s->closed){result=failure(EINVAL);return;}
        if(strcmp(name,"active")==0)*out=value_t(s->active&&activeHandle==handle);
        else if(strcmp(name,"focus")==0)*out=value_t(s->focused);
        else if(strcmp(name,"motion")==0)*out=value_t(s->moving);
        else if(strcmp(name,"device.present")==0)*out=value_t(std::any_of(s->devices.begin(),s->devices.end(),[](const auto& d){return d.id!=0;}));
        else if(strcmp(name,"frame.timingSource")==0)*out=value_t(long(s->clientTiming));
        else if(!s->get(name,*out))result=failure(navlib_errc::property_not_found);
    });return result;
}
long NlWriteValue(nlHandle_t handle,property_t name,const value_t* value){
    auto s=find(handle);if(!s||!name||!value)return failure(EINVAL);
    auto type=NlGetType(name);if(type==unknown_type)return failure(navlib_errc::property_not_found);
    if(value->type!=type&&!(type==string_type&&value->type==cstr_type))return failure(EINVAL);
    __block long result=0;
    s->sync(^{
        if(s->closed){result=failure(EINVAL);return;}
        if(strcmp(name,"active")==0||strcmp(name,"focus")==0){
            if(strcmp(name,"active")==0)s->active=value->b;else s->focused=value->b;
            if(value->b)activeHandle=handle;else{nlHandle_t expected=handle;activeHandle.compare_exchange_strong(expected,0);}
            if(!value->b)s->stopMotion();return;
        }
        if(strcmp(name,"motion")==0){if(!value->b)s->stopMotion();return;}
        if(strcmp(name,"frame.timingSource")==0){if(value->l!=0&&value->l!=1){result=failure(EINVAL);return;}s->clientTiming=value->l;s->lastFrame=0;s->clientFrame=0;s->updateFrameClock();return;}
        if(strcmp(name,"frame.time")==0){if(!std::isfinite(value->d)){result=failure(EINVAL);return;}double dt=s->clientFrame>0?(value->d-s->clientFrame)/1000:1.0/120;s->clientFrame=value->d;if(s->clientTiming&&dt>0)s->frame(dt);return;}
        if(strcmp(name,"commands.tree")==0){publishCommands(*s,value->pnode);return;}
        if(strcmp(name,"images")==0)return;
        Slot& slot=s->properties[name];slot.name=name;
        if(type==string_type){const char* p=value->type==cstr_type?value->cstr_.p:value->string.p;size_t n=value->type==cstr_type?value->cstr_.length:value->string.length;
            if(!p||n>65536){result=failure(EINVAL);return;}slot.text.assign(p,strnlen(p,n));slot.cached.type=string_type;slot.cached.string={slot.text.data(),slot.text.size()+1};
        } else slot.cached=*value;
        slot.hasValue=true;
    });return result;
}
}
