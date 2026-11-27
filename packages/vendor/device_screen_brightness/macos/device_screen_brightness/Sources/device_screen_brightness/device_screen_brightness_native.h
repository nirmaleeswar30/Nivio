#ifndef DEVICE_SCREEN_BRIGHTNESS_NATIVE_H
#define DEVICE_SCREEN_BRIGHTNESS_NATIVE_H

#include <stdint.h>

#define DSB_OK 0
#define DSB_UNSUPPORTED_OPERATION 1
#define DSB_PERMISSION_DENIED 2
#define DSB_NATIVE_FAILURE 3
#define DSB_INVALID_VALUE 4
#define DSB_BACKEND_NOT_AVAILABLE 5

typedef struct {
  int32_t value;
  int32_t min;
  int32_t max;
  int32_t reserved;
  int32_t error_code;
} DeviceScreenBrightnessResult;

DeviceScreenBrightnessResult device_screen_brightness_get(void);
DeviceScreenBrightnessResult device_screen_brightness_set(int32_t value);
DeviceScreenBrightnessResult device_screen_brightness_increment(void);
DeviceScreenBrightnessResult device_screen_brightness_decrement(void);

#endif
