#ifndef SMCParamStruct_h
#define SMCParamStruct_h

#include <stdint.h>
#include <IOKit/IOTypes.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Private IOPM functions for sleep management
CFDictionaryRef IOPMCopySystemPowerSettings(void);
IOReturn IOPMSetSystemPowerSetting(CFStringRef key, CFTypeRef value);
#define kIOPMSleepDisabledKey CFSTR("SleepDisabled")

enum {
    kSMCSuccess         = 0,
    kSMCError           = 1
};

enum {
    kSMCUserClientOpen  = 0,
    kSMCUserClientClose = 1,
    kSMCHandleYPCEvent  = 2,
    kSMCReadKey         = 5,
    kSMCWriteKey        = 6,
    kSMCGetKeyCount     = 7,
    kSMCGetKeyFromIndex = 8,
    kSMCGetKeyInfo      = 9
};

typedef struct {
    unsigned char    major;
    unsigned char    minor;
    unsigned char    build;
    unsigned char    reserved;
    unsigned short   release;
} SMCVersion;

typedef struct {
    uint16_t    version;
    uint16_t    length;
    uint32_t    cpuPLimit;
    uint32_t    gpuPLimit;
    uint32_t    memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t            dataSize;
    uint32_t            dataType;
    uint8_t             dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t            key;
    SMCVersion          vers;
    SMCPLimitData       pLimitData;
    SMCKeyInfoData      keyInfo;
    uint8_t             result;
    uint8_t             status;
    uint8_t             data8;
    uint32_t            data32;
    uint8_t             bytes[32];
} SMCParamStruct;

#ifdef __cplusplus
}
#endif

#endif /* SMCParamStruct_h */
