#include "axial/application.hpp"
#include "axial/application_buttons.hpp"
#include <map>
#include <iostream>
#define CHECK(x) do {if(!(x)){std::cerr<<__LINE__<<": " #x "\n";return 1;}}while(0)
int main(){
    using sn::ProcessIdentity;
    ProcessIdentity app{100,1,501,123,"/Applications/Test.app/Contents/MacOS/Test"};
    ProcessIdentity helper{101,100,501,124,"/Applications/Test.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"};
    std::map<pid_t,ProcessIdentity> processes{{100,app},{101,helper}};
    auto lookup=[&](pid_t pid){auto it=processes.find(pid);return it==processes.end()?ProcessIdentity{}:it->second;};
    CHECK(sn::belongsToApplication(app,app,lookup));
    CHECK(sn::belongsToApplication(helper,app,lookup));
    auto child=helper;child.pid=102;child.parent=101;CHECK(sn::belongsToApplication(child,app,lookup));
    child.uid=502;CHECK(!sn::belongsToApplication(child,app,lookup));
    child=helper;child.executable="/Applications/Other.app/Contents/MacOS/Other";CHECK(!sn::belongsToApplication(child,app,lookup));
    child=helper;child.parent=1;CHECK(!sn::belongsToApplication(child,app,lookup));
    processes[100].birth=999;CHECK(!sn::belongsToApplication(helper,app,lookup));
    processes.erase(100);CHECK(!sn::belongsToApplication(helper,app,lookup));
    CHECK(sn::processIdentity(getpid()).pid==getpid());
    CHECK(sn::applicationButton(0x046d,0xc627,10)==2);
    CHECK(sn::applicationButton(0x256f,0xc633,6)==77);
    CHECK(sn::applicationButton(0x256f,0xc635,0)==1);
    CHECK(sn::applicationButton(0,0,0)==0);
    std::cout<<"Application ownership and semantic button contracts passed\n";
}
