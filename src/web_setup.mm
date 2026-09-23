#import <Foundation/Foundation.h>
#include <Security/Security.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <openssl/x509v3.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <spawn.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
extern char** environ;
namespace {
NSString* const directory=@"/Library/Application Support/Axial/Web";
NSString* const parent=@"/Library/Application Support/Axial";
NSString* const daemon=@"/Library/LaunchDaemons/pro.jest.axial-web-loopback.plist";
NSString* const label=@"pro.jest.axial-web-loopback";
void require(bool ok,const char* message){if(!ok)throw std::runtime_error(message);}
int run(std::initializer_list<std::string> arguments){
    std::vector<std::string> storage(arguments);std::vector<char*> argv;
    for(auto& arg:storage)argv.push_back(arg.data());argv.push_back(nullptr);
    pid_t child;int result=posix_spawn(&child,argv[0],nullptr,nullptr,argv.data(),environ);
    if(result)return result;
    int status=0;while(waitpid(child,&status,0)<0){if(errno!=EINTR)return errno;}
    return WIFEXITED(status)?WEXITSTATUS(status):1;
}
void command(std::initializer_list<std::string> args){require(run(args)==0,"macOS web setup command failed");}
void checkDirectory(NSString* path,mode_t mode){
    struct stat st{};
    if(lstat(path.fileSystemRepresentation,&st)){
        require(errno==ENOENT&&mkdir(path.fileSystemRepresentation,mode)==0,"Cannot create credential directory");
        require(lstat(path.fileSystemRepresentation,&st)==0,"Cannot inspect credential directory");
    }
    require(S_ISDIR(st.st_mode)&&st.st_uid==geteuid(),"Credential directory must be owned by the installing user and cannot be a symlink");
    require(chmod(path.fileSystemRepresentation,mode)==0,"Cannot protect credential directory");
}
std::string path(NSString* base,const char* name){return [[base stringByAppendingPathComponent:@(name)] fileSystemRepresentation];}
void checkFile(const std::string& file){
    struct stat st{};if(lstat(file.c_str(),&st)==0)require(S_ISREG(st.st_mode)&&st.st_uid==geteuid()&&st.st_nlink==1,"Unsafe credential file");
    else require(errno==ENOENT,"Cannot inspect credential file");
}
using Key=std::unique_ptr<EVP_PKEY,decltype(&EVP_PKEY_free)>;
using Certificate=std::unique_ptr<X509,decltype(&X509_free)>;
Key key(){Key result(EVP_PKEY_Q_keygen(nullptr,nullptr,"RSA",3072),EVP_PKEY_free);require(bool(result),"Key generation failed");return result;}
Certificate certificate(EVP_PKEY* key,const char* commonName,long days){
    Certificate cert(X509_new(),X509_free);require(bool(cert),"Certificate allocation failed");
    require(X509_set_version(cert.get(),2)==1,"Certificate version failed");
    unsigned char serial[16];require(RAND_bytes(serial,sizeof(serial))==1,"Serial generation failed");serial[0]&=0x7f;
    BIGNUM* bn=BN_bin2bn(serial,sizeof(serial),nullptr);require(bn!=nullptr,"Serial allocation failed");
    ASN1_INTEGER* value=BN_to_ASN1_INTEGER(bn,nullptr);BN_free(bn);require(value!=nullptr,"Serial encoding failed");
    int result=X509_set_serialNumber(cert.get(),value);ASN1_INTEGER_free(value);require(result==1,"Serial assignment failed");
    require(X509_gmtime_adj(X509_getm_notBefore(cert.get()),-300)!=nullptr&&X509_gmtime_adj(X509_getm_notAfter(cert.get()),days*24*3600)!=nullptr,"Certificate validity failed");
    require(X509_set_pubkey(cert.get(),key)==1,"Certificate public key failed");
    require(X509_NAME_add_entry_by_txt(X509_get_subject_name(cert.get()),"CN",MBSTRING_ASC,reinterpret_cast<const unsigned char*>(commonName),-1,-1,0)==1,"Certificate subject failed");
    return cert;
}
void extension(X509* cert,X509* issuer,int nid,const char* value){
    X509V3_CTX context;X509V3_set_ctx(&context,issuer,cert,nullptr,nullptr,0);
    X509_EXTENSION* ext=X509V3_EXT_conf_nid(nullptr,&context,nid,value);require(ext!=nullptr,"Certificate extension failed");
    int result=X509_add_ext(cert,ext,-1);X509_EXTENSION_free(ext);require(result==1,"Certificate extension assignment failed");
}
template<class Writer> void write(const std::string& path,Writer writer){
    int fd=open(path.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);require(fd>=0,"Credential already exists or cannot be written");
    FILE* file=fdopen(fd,"w");if(!file){close(fd);throw std::runtime_error("Cannot open credential stream");}
    bool ok=writer(file)==1;int sync=fflush(file);if(sync==0)sync=fsync(fd);int closed=fclose(file);
    require(ok&&sync==0&&closed==0,"Cannot save credentials");
}
void prepare(NSString* target){
    checkDirectory(target,0700);
    for(const char* name:{"root.crt","server.crt","server.key"}){
        auto file=path(target,name);struct stat st{};require(lstat(file.c_str(),&st)!=0&&errno==ENOENT,"Credentials already exist");
    }
    auto rootKey=key(),serverKey=key();
    auto root=certificate(rootKey.get(),[[NSString stringWithFormat:@"Axial Local Web CA %@",NSUUID.UUID.UUIDString] UTF8String],3650);
    X509_set_issuer_name(root.get(),X509_get_subject_name(root.get()));
    extension(root.get(),root.get(),NID_basic_constraints,"critical,CA:TRUE,pathlen:0");
    extension(root.get(),root.get(),NID_key_usage,"critical,keyCertSign,cRLSign");
    extension(root.get(),root.get(),NID_subject_key_identifier,"hash");
    require(X509_sign(root.get(),rootKey.get(),EVP_sha256())>0,"CA signing failed");
    // macOS also caps privately issued TLS leaf validity at 825 days.
    auto server=certificate(serverKey.get(),"Axial loopback",730);X509_set_issuer_name(server.get(),X509_get_subject_name(root.get()));
    extension(server.get(),root.get(),NID_basic_constraints,"critical,CA:FALSE");
    extension(server.get(),root.get(),NID_key_usage,"critical,digitalSignature,keyEncipherment");
    extension(server.get(),root.get(),NID_ext_key_usage,"serverAuth");
    extension(server.get(),root.get(),NID_subject_alt_name,"IP:127.51.68.120");
    require(X509_sign(server.get(),rootKey.get(),EVP_sha256())>0,"Server signing failed");
    write(path(target,"server.key"),[&](FILE* f){return PEM_write_PrivateKey(f,serverKey.get(),nullptr,nullptr,0,nullptr,nullptr);});
    write(path(target,"server.crt"),[&](FILE* f){return PEM_write_X509(f,server.get());});
    write(path(target,"root.crt"),[&](FILE* f){return PEM_write_X509(f,root.get());});
    // The CA private key never leaves memory and is freed here.
}
Certificate readCertificate(const std::string& file){
    FILE* f=fopen(file.c_str(),"r");if(!f)return {nullptr,X509_free};
    Certificate cert(PEM_read_X509(f,nullptr,nullptr,nullptr),X509_free);fclose(f);return cert;
}
bool validCredentials(NSString* target){
    auto root=readCertificate(path(target,"root.crt")),server=readCertificate(path(target,"server.crt"));
    time_t renewal=time(nullptr)+90L*24*3600;
    if(!root||!server||X509_cmp_time(X509_get0_notAfter(root.get()),&renewal)<=0||X509_cmp_time(X509_get0_notAfter(server.get()),&renewal)<=0||X509_check_ip_asc(server.get(),"127.51.68.120",0)!=1)return false;
    int days=0,seconds=0;
    if(X509_cmp_current_time(X509_get0_notBefore(server.get()))>=0||ASN1_TIME_diff(&days,&seconds,X509_get0_notBefore(server.get()),X509_get0_notAfter(server.get()))!=1||days>825||(days==825&&seconds>0))return false;
    Key publicKey(X509_get_pubkey(root.get()),EVP_PKEY_free);if(!publicKey||X509_verify(server.get(),publicKey.get())!=1)return false;
    FILE* file=fopen(path(target,"server.key").c_str(),"r");if(!file)return false;
    Key privateKey(PEM_read_PrivateKey(file,nullptr,nullptr,nullptr),EVP_PKEY_free);fclose(file);
    return privateKey&&X509_check_private_key(server.get(),privateKey.get())==1;
}
void untrust(NSString* target){
    auto root=readCertificate(path(target,"root.crt"));if(!root)return;
    unsigned char digest[EVP_MAX_MD_SIZE];unsigned length=0;
    require(X509_digest(root.get(),EVP_sha1(),digest,&length)==1,"Cannot identify CA certificate");
    std::string fingerprint;for(unsigned i=0;i<length;++i){char hex[3];snprintf(hex,sizeof(hex),"%02X",digest[i]);fingerprint+=hex;}
    run({"/usr/bin/security","remove-trusted-cert","-d",path(target,"root.crt")});
    run({"/usr/bin/security","delete-certificate","-Z",fingerprint,"/Library/Keychains/System.keychain"});
}
bool hasAlias(){
    // getifaddrs avoids parsing command output or invoking a shell.
    struct ifaddrs* addresses=nullptr;if(getifaddrs(&addresses)!=0)throw std::runtime_error("Cannot inspect loopback addresses");
    bool found=false;for(auto p=addresses;p;p=p->ifa_next)if(p->ifa_addr&&p->ifa_addr->sa_family==AF_INET&&strcmp(p->ifa_name,"lo0")==0){
        auto a=reinterpret_cast<sockaddr_in*>(p->ifa_addr);found|=ntohl(a->sin_addr.s_addr)==0x7f334478;
    }
    freeifaddrs(addresses);return found;
}
void storeCertificate(){
    auto root=readCertificate(path(directory,"root.crt"));require(bool(root),"Cannot read web CA");
    int length=i2d_X509(root.get(),nullptr);require(length>0,"Cannot encode web CA");
    std::vector<unsigned char> bytes(length);auto output=bytes.data();
    require(i2d_X509(root.get(),&output)==length,"Cannot encode web CA");
    NSData* data=[NSData dataWithBytes:bytes.data() length:bytes.size()];
    SecCertificateRef certificate=SecCertificateCreateWithData(nullptr,(__bridge CFDataRef)data);
    require(certificate!=nullptr,"Cannot import web CA");
    SecKeychainRef keychain=nullptr;
    OSStatus result=SecKeychainOpen("/Library/Keychains/System.keychain",&keychain);
    if(result==errSecSuccess)result=SecCertificateAddToKeychain(certificate,keychain);
    if(keychain)CFRelease(keychain);CFRelease(certificate);
    // Repeated setup and recovery after partial setup must be idempotent.
    require(result==errSecSuccess||result==errSecDuplicateItem,"Cannot store the local web certificate in the system keychain");
}
bool ownDaemon(){
    struct stat st{};if(lstat(daemon.fileSystemRepresentation,&st))return false;
    require(S_ISREG(st.st_mode)&&st.st_uid==0,"Unsafe loopback configuration");
    NSDictionary* doc=[NSDictionary dictionaryWithContentsOfFile:daemon];
    require([doc[@"Label"] isEqual:label]&&[doc[@"ProgramArguments"] isEqual:@[@"/sbin/ifconfig",@"lo0",@"alias",@"127.51.68.120",@"netmask",@"255.0.0.0"]],"Foreign loopback configuration");return true;
}
void install(){
    require(geteuid()==0,"Web setup requires the installer or administrator access");
    checkDirectory(parent,0755);checkDirectory(directory,0750);
    for(const char* name:{"root.crt","server.crt","server.key"})checkFile(path(directory,name));
    if(!validCredentials(directory)){
        auto temporary=path(directory,"generate.XXXXXX");std::vector<char> name(temporary.begin(),temporary.end());name.push_back(0);
        require(mkdtemp(name.data())!=nullptr,"Cannot prepare credentials");NSString* staging=@(name.data());
        try{
            prepare(staging);untrust(directory);
            for(const char* file:{"root.crt","server.crt","server.key"})require(rename(path(staging,file).c_str(),path(directory,file).c_str())==0,"Cannot install credentials");
        }catch(...){for(const char* file:{"root.crt","server.crt","server.key"})unlink(path(staging,file).c_str());rmdir(name.data());throw;}
        rmdir(name.data());
    }
    require(chown(directory.fileSystemRepresentation,0,20)==0,"Cannot set credential group");
    for(const char* file:{"root.crt","server.crt","server.key"}){
        auto name=path(directory,file);require(chown(name.c_str(),0,20)==0&&chmod(name.c_str(),strcmp(file,"server.key")==0?0640:0644)==0,"Cannot protect credentials");
    }
    // Store the public certificate only. The GUI app requests trust separately
    // using Security.framework in the logged-in user's authorization session.
    storeCertificate();
    bool owned=ownDaemon();if(!owned&&hasAlias())return;
    if(!owned){
        NSDictionary* doc=@{@"Label":label,@"ProgramArguments":@[@"/sbin/ifconfig",@"lo0",@"alias",@"127.51.68.120",@"netmask",@"255.0.0.0"],@"RunAtLoad":@YES};
        NSData* data=[NSPropertyListSerialization dataWithPropertyList:doc format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
        require(data!=nil&&[data writeToFile:daemon options:NSDataWritingWithoutOverwriting error:nil],"Cannot install loopback configuration");
        require(chmod(daemon.fileSystemRepresentation,0644)==0,"Cannot set loopback configuration permissions");
        command({"/bin/launchctl","bootstrap","system",daemon.fileSystemRepresentation});
    }
    if(!hasAlias())command({"/sbin/ifconfig","lo0","alias","127.51.68.120","netmask","255.0.0.0"});
}
void uninstall(){
    require(geteuid()==0,"Web removal requires administrator access");
    if(ownDaemon()){
        run({"/bin/launchctl","bootout","system",daemon.fileSystemRepresentation});
        if(hasAlias())command({"/sbin/ifconfig","lo0","-alias","127.51.68.120"});
        require(unlink(daemon.fileSystemRepresentation)==0,"Cannot remove loopback configuration");
    }
    struct stat st{};if(lstat(directory.fileSystemRepresentation,&st)!=0){require(errno==ENOENT,"Cannot inspect credential directory");return;}
    checkDirectory(parent,0755);checkDirectory(directory,0750);
    for(const char* name:{"root.crt","server.crt","server.key"})checkFile(path(directory,name));
    untrust(directory);
    for(const char* name:{"root.crt","server.crt","server.key"})if(unlink(path(directory,name).c_str())!=0)require(errno==ENOENT,"Cannot remove credential");
    require(rmdir(directory.fileSystemRepresentation)==0,"Cannot remove credential directory");
}
}
int main(int argc,char** argv){@autoreleasepool {try{
    OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG,nullptr);
    if(argc==3&&strcmp(argv[1],"--prepare")==0){prepare(@(argv[2]));return 0;}
    if(argc==2&&strcmp(argv[1],"--uninstall")==0){uninstall();return 0;}
    if(argc==2&&strcmp(argv[1],"--install")==0){install();return 0;}
    if(argc==2&&strcmp(argv[1],"--check")==0){
        NSDictionary* state=@{@"credentialsReady":@(validCredentials(directory)),@"loopbackReady":@(hasAlias())};
        NSData* data=[NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
        fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);return 0;
    }
    fprintf(stderr,"usage: axial-web-setup --install|--uninstall|--check|--prepare directory\n");return 2;
}catch(const std::exception& error){fprintf(stderr,"Axial web setup: %s\n",error.what());return 1;}}}
