#include "web_client.hpp"
#include "axial/transport.hpp"
#include <sys/resource.h>
double cpu() {rusage u{};getrusage(RUSAGE_SELF,&u);return u.ru_utime.tv_sec+u.ru_stime.tv_sec+(u.ru_utime.tv_usec+u.ru_stime.tv_usec)/1e6;}
int main(int argc,char** argv) {try {
    if(argc<2)return 2;std::string directory=argv[1];double seconds=argc>2?std::stod(argv[2]):5;if(seconds<=0)return 2;
    sn::WebServer server("127.0.0.1",0);sn::WebConfiguration config;
    config.certificate=directory+"/server.crt";config.key=directory+"/server.key";server.configure(config);
    json::object status;
    for(int i=0;i<300;++i){status=json::parse(server.status()).as_object();if(status["listening"]==true)break;std::this_thread::sleep_for(std::chrono::milliseconds(10));}
    CHECK(status["listening"]==true);
    Client client(status["port"].to_number<unsigned>(),directory+"/root.crt");client.connect();
    client.send(json::array{1,"self","https://benchmark.example"});
    auto mouse=client.call({2,"mouse","rpc:create","3dconnexion:3dmouse","0.7.0"}).as_object()["connexion"];
    auto controller=client.call({2,"controller","rpc:create","3dconnexion:3dcontroller",mouse,json::object{{"name","Axial benchmark"}}}).as_object()["instance"];
    client.send(json::array{5,controller});client.call({2,"focus","rpc:update",controller,json::object{{"focus",true}}});
    sn::Event event;event.device=1;event.vendor=0x046d;event.product=0xc627;event.kind=sn::Kind::added;server.receive(event);
    std::atomic<bool> stopping=false,failed=false;
    int descriptor=beast::get_lowest_layer(client.socket).socket().native_handle();
    // A blocking reader also drains frames already buffered by Beast; polling
    // the underlying descriptor alone can strand buffered callback requests.
    std::thread reader([&]{try {while(!stopping)client.callback(client.read());}catch(...){if(!stopping)failed=true;}});
    bool valid=true;
    for(const char* mode:{"idle","moving","stopped"}) {
        bool moving=!strcmp(mode,"moving");event.kind=sn::Kind::motion;event.axes={};if(moving)event.axes={100,0,0,30,0,0};
        auto run=[&](double duration) {
            auto end=std::chrono::steady_clock::now()+std::chrono::duration<double>(duration);
            do {event.received=sn::now();server.receive(event);
                std::this_thread::sleep_until(moving?std::min(end,std::chrono::steady_clock::now()+std::chrono::duration<double>(.008)):end);
            }while(std::chrono::steady_clock::now()<end);
        };
        run(.5);int frames=client.matrices;double initial=cpu();auto start=sn::now();run(seconds);
        double elapsed=double(sn::now()-start)/1e9;frames=client.matrices-frames;
        valid&=moving?frames>0:frames==0;
        std::cout<<"{\"mode\":\""<<mode<<"\",\"seconds\":"<<elapsed<<",\"combined_cpu_percent\":"<<(cpu()-initial)/elapsed*100<<",\"frames\":"<<frames<<"}\n";
    }
    stopping=true;::shutdown(descriptor,SHUT_RDWR);reader.join();
    return valid&&!failed?0:1;
}catch(const std::exception& error){std::cerr<<error.what()<<"\n";return 1;}}
