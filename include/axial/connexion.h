#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#pragma pack(push,2)
typedef struct ConnexionDeviceState {
    uint16_t version,client,command;
    int16_t param;
    int32_t value;
    uint64_t time;
    uint8_t report[8];
    uint16_t buttons8;
    int16_t axis[6];
    uint16_t address;
    uint32_t buttons;
} ConnexionDeviceState;
#pragma pack(pop)
typedef void (*ConnexionMessageHandler)(uint32_t,uint32_t,void*);
typedef void (*ConnexionDeviceHandler)(uint32_t);
int16_t SetConnexionHandlers(ConnexionMessageHandler,ConnexionDeviceHandler,ConnexionDeviceHandler,bool);
int16_t InstallConnexionHandlers(ConnexionMessageHandler,ConnexionDeviceHandler,ConnexionDeviceHandler);
void CleanupConnexionHandlers(void);
uint16_t RegisterConnexionClient(uint32_t,const uint8_t*,uint16_t,uint32_t);
void UnregisterConnexionClient(uint16_t);
void SetConnexionClientMask(uint16_t,uint32_t);
void SetConnexionClientButtonMask(uint16_t,uint32_t);
int16_t ConnexionClientControl(uint16_t,uint32_t,int32_t,int32_t*);
int16_t ConnexionControl(uint32_t,int32_t,int32_t*);
#ifdef __cplusplus
}
static_assert(sizeof(ConnexionDeviceState)==48);
static_assert(__builtin_offsetof(ConnexionDeviceState,axis)==30);
#endif
