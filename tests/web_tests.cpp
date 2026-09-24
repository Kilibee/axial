#include "web_client.hpp"
int main(int argc,char** argv){try{
    CHECK(argc==2);std::string directory=argv[1];
    sn::WebServer server("127.0.0.1",0);sn::WebConfiguration config;
    config.certificate=directory+"/server.crt";config.key=directory+"/server.key";server.configure(config);
    json::object status;
    for(int i=0;i<300;++i){status=json::parse(server.status()).as_object();if(status["listening"]==true)break;std::this_thread::sleep_for(std::chrono::milliseconds(10));}
    CHECK(status["listening"]==true);unsigned port=status["port"].to_number<unsigned>();
    for(const auto& origin:{"https://unlisted.example","http://untrusted.example"}){
        Client client(port,directory+"/root.crt");http::request<http::empty_body> request{http::verb::get,"/3dconnexion/nlproxy",11};
        request.set(http::field::host,client.host);request.set(http::field::origin,origin);
        http::write(client.socket.next_layer(),request);http::response<http::string_body> response;beast::flat_buffer buffer;http::read(client.socket.next_layer(),buffer,response);
        CHECK(response.result()==(std::string(origin).starts_with("https:")?http::status::ok:http::status::forbidden));
        if(response.result()==http::status::ok)CHECK(json::parse(response.body()).as_object()["port"].to_number<unsigned>()==port);
    }
    Client client(port,directory+"/root.crt");client.connect();
    // Replay the browser's 0.7.0 handshake: RPC targets are controller CURIEs,
    // not the bare instance IDs returned by create.
    client.send(json::array{1,"3dx_rpc","wss://127.51.68.120/3dconnexion#"});
    client.send(json::array{1,"3dconnexion","wss://127.51.68.120/3dconnexion"});
    client.send(json::array{1,"self","https://3dconnexion.com/technical_support/web_threejs.html"});
    auto mouse=client.call({2,"mouse","3dx_rpc:create","3dconnexion:3dmouse","0.7.0"}).as_object()["connexion"];
    auto controller=client.call({2,"controller","3dx_rpc:create","3dconnexion:3dcontroller",mouse,json::object{{"name","WebThreeJS Sample"},{"version",0.7},{"rowMajorOrder",false}}}).as_object()["instance"];
    auto compact="3dconnexion:3dcontroller/"+text(controller);
    auto full="wss://127.51.68.120/3dconnexion3dcontroller/"+text(controller);
    client.send(json::array{5,compact});
    client.call({2,"focus","3dx_rpc:update",compact,json::object{{"focus",true}}});
    client.call({2,"frame","3dx_rpc:update",compact,json::object{{"frame",json::object{{"timingSource",1}}}}});
    auto commands=json::parse(R"({"activeSet":"Default","tree":{"nodes":[{"id":"Default","label":"Custom action set","type":0,"nodes":[{"id":"CAT_ID_FILE","label":"File","type":1,"nodes":[{"id":"ID_OPEN","label":"Open","type":2,"description":"Open file"}]}]}]}})");
    client.call({2,"commands","3dx_rpc:update",compact,json::object{{"commands",commands}}});
    CHECK(client.call({2,"commands-read","rpc:read",full,"commands"})==commands);
    CHECK(client.call({2,"focused","rpc:read",compact,"focus"})==true);
    sn::Event e;e.device=1;e.vendor=0x046d;e.product=0xc627;e.kind=sn::Kind::added;server.receive(e);
    e.kind=sn::Kind::motion;e.axes[0]=350;e.flags=sn::Flags::orbit;server.receive(e);
    while(client.matrices<2||client.transaction)client.callback(client.read());
    CHECK(client.matrix[12].to_number<double>()>0);CHECK(client.moving);
    e.axes={};server.receive(e);while(client.moving)client.callback(client.read());
    client.call({2,"blur","rpc:update",controller,json::object{{"focus",false}}});
    CHECK(client.call({2,"focused","rpc:read",controller,"focus"})==false);
    // Bare IDs, declared prefixes and full URIs address the same session-local
    // controller; unrelated namespaces and other sessions cannot alias it.
    client.send(json::array{1,"alias","wss://127.51.68.120/3dconnexion"});
    for(const auto& reference:{text(controller),compact,full,"alias:3dcontroller/"+text(controller)}){
        client.send(json::array{5,reference});
        client.call({2,"refocus","rpc:update",reference,json::object{{"focus",true}}});
        CHECK(client.call({2,"focused","rpc:read",reference,"focus"})==true);
        client.send(json::array{6,reference});
        CHECK(client.call({2,"unsubscribed","rpc:read",reference,"focus"})==false);
    }
    CHECK(json::parse(server.status()).as_object()["unsupported"]==0);
    client.unknownController("wss://unrelated.example/3dconnexion3dcontroller/"+text(controller));
    client.unknownController("undeclared:3dcontroller/"+text(controller));
    {Client other(port,directory+"/root.crt");other.connect();other.unknownController(full);}
    client.send(json::array{2,"unknown","rpc:unsupported"});
    auto error=client.read();CHECK(error[0]==4&&error[1]=="unknown");
    for(const auto& prefix:{"","3dconnexion:3dcontroller/","wss://127.51.68.120/3dconnexion3dcontroller/"}){
        auto second=client.call({2,"controller2","rpc:create","3dconnexion:3dcontroller",mouse,json::object{{"name","Second view"}}}).as_object()["instance"];
        CHECK(second!=controller);client.call({2,"delete","rpc:delete",prefix+text(second)});
        client.unknownController(text(second));
    }
    sn::WebServer conflict("127.0.0.1",port);conflict.configure(config);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));CHECK(json::parse(conflict.status()).as_object()["listening"]==false);
    config.enabled=false;server.configure(config);
    for(int i=0;i<100;++i){status=json::parse(server.status()).as_object();if(status["listening"]==false)break;std::this_thread::sleep_for(std::chrono::milliseconds(10));}
    CHECK(status["listening"]==false);
    // An explicit retry must preserve the enabled preference.
    server.retry();std::this_thread::sleep_for(std::chrono::milliseconds(30));
    CHECK(json::parse(server.status()).as_object()["listening"]==false);
    // Destroying a live server closes both active WebSockets and its listener.
    config.enabled=true;auto lifetime=std::make_unique<sn::WebServer>("127.0.0.1",0);lifetime->configure(config);
    for(int i=0;i<300;++i){status=json::parse(lifetime->status()).as_object();if(status["listening"]==true)break;std::this_thread::sleep_for(std::chrono::milliseconds(10));}
    CHECK(status["listening"]==true);auto lifetimePort=status["port"].to_number<unsigned>();
    Client connected(lifetimePort,directory+"/root.crt");connected.connect();lifetime.reset();
    bool closed=false;try{connected.read();}catch(const boost::system::system_error&){closed=true;}CHECK(closed);
    net::io_context probeIO;tcp::socket probe(probeIO);boost::system::error_code connectError;
    probe.connect(tcp::endpoint(net::ip::make_address("127.0.0.1"),lifetimePort),connectError);CHECK(bool(connectError));
    std::cout<<"TLS, discovery, origins, WAMP lifecycle, camera callbacks, neutral, focus and port conflict passed\n";
    return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
