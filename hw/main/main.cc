#include <bitset>

#include "bt.h"

#define AC_ENABLE 34
#define TEMP_ADC 1

uint32_t cook_ms_remaining = 30 * 60 * 1000;          // 30 minutes
uint32_t incubate_ms_remaining = 8 * 60 * 60 * 1000;  // 8 hours. TODO: pH

std::bitset<8> status;
size_t StatusRunning = 0;
size_t StatusCooking = 1;
size_t StatusCooling = 2;
size_t StatusIncubating = 3;

BtService* bts;

class StatusCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* ch) { status = ch->getValue()[0]; }
};

class IncubationTimeCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* ch) {
    incubate_ms_remaining =
        reinterpret_cast<const uint32_t*>(ch->getValue().data())[0];
  }
};

uint32_t last_millis;

void setup() {
  Serial.begin(115200);
  bts = new BtService(new StatusCallbacks(), new IncubationTimeCallbacks());
  bts->notifyCookTime(cook_ms_remaining);
  bts->notifyIncubationTime(incubate_ms_remaining);
  Serial.println("Ready.");
}

struct ControlParams {
  std::bitset<8> next_status;
  bool heater_on;
} ctrl;

void runControl(uint32_t time_delta_ms) {
  ctrl.next_status = status;
  ctrl.heater_on = false;

  if (!status[StatusRunning])
    return;

  // int16_t current_temp = analogRead(TEMP_ADC);
  int16_t current_temp;
  int16_t target_temp = status[StatusCooking] ? 85 : 43;  // degrees C

  current_temp = target_temp;

  if (status[StatusCooling]) {
    if (current_temp <= target_temp) {
      ctrl.next_status.reset();
      ctrl.next_status.set(StatusIncubating, true);
    }
    return;
  }

  uint32_t* ms_remaining;
  void (BtService::*time_notifier)(uint32_t);
  size_t next_status_bit;

  if (status[StatusCooking]) {
    ms_remaining = &cook_ms_remaining;
    time_notifier = &BtService::notifyCookTime;
    next_status_bit = StatusCooling;
  } else if (status[StatusIncubating]) {
    ms_remaining = &incubate_ms_remaining;
    time_notifier = &BtService::notifyIncubationTime;
    next_status_bit = StatusRunning;
  } else {
    return;
  }

  // TODO: tune params
  if (abs(current_temp - target_temp) < 5) {
    if (*ms_remaining > time_delta_ms) {
      *ms_remaining -= time_delta_ms;
      (bts->*time_notifier)(*ms_remaining);
    } else {
      *ms_remaining = 0;
      ctrl.next_status.reset(StatusCooking);
      ctrl.next_status.reset(StatusCooling);
      ctrl.next_status.reset(StatusIncubating);
      ctrl.next_status.flip(next_status_bit);
    }
    (bts->*time_notifier)(*ms_remaining);
  } else {
    ctrl.heater_on = true;
  }
}

void loop() {
  std::bitset<8> last_status(status);
  uint32_t now = millis();
  runControl(last_millis == 0 ? 0 : now - last_millis);
  if (status != ctrl.next_status) {
    status = ctrl.next_status;
    bts->notifyStatus(status);
  }
  digitalWrite(AC_ENABLE, ctrl.heater_on);
  last_millis = now;
  delay(500);
}
