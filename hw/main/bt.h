#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#define SERVICE_UUID "864ca7a0-268c-4224-96d3-1982825571f0"
#define STATUS_CHARACTERISTIC "864ca7a1-268c-4224-96d3-1982825571f0"
#define COOK_TIME_CHARACTERISTIC "864ca7a2-268c-4224-96d3-1982825571f0"
#define INCUBATION_TIME_CHARACTERISTIC "864ca7a3-268c-4224-96d3-1982825571f0"
#define CUR_TEMPS_CHARACTERISTIC "864ca7a4-268c-4224-96d3-1982825571f0"
#define FETCH_CHARTS_CHARACTERISTIC "864ca7a5-268c-4224-96d3-1982825571f0"

class BtService {
 public:
  BtService(BLECharacteristicCallbacks* status_cb,
            BLECharacteristicCallbacks* incubation_time_cb) {
    BLEDevice::init("Legal Yogurt Maker");
    server_ = BLEDevice::createServer();
    BLEService* service = server_->createService(SERVICE_UUID);

    status_ch_ = service->createCharacteristic(
        STATUS_CHARACTERISTIC, BLECharacteristic::PROPERTY_READ |
                                   BLECharacteristic::PROPERTY_WRITE |
                                   BLECharacteristic::PROPERTY_NOTIFY);
    status_ch_->setCallbacks(status_cb);
    status_ch_->addDescriptor(new BLE2902());

    cook_ch_ = service->createCharacteristic(
        COOK_TIME_CHARACTERISTIC,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    cook_ch_->addDescriptor(new BLE2902());

    incubation_ch_ = service->createCharacteristic(
        INCUBATION_TIME_CHARACTERISTIC, BLECharacteristic::PROPERTY_READ |
                                            BLECharacteristic::PROPERTY_WRITE |
                                            BLECharacteristic::PROPERTY_NOTIFY);
    incubation_ch_->setCallbacks(incubation_time_cb);
    incubation_ch_->addDescriptor(new BLE2902());

    service->start();

    BLEAdvertising* advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(SERVICE_UUID);
    advertising->setScanResponse(true);
    // functions that help with iPhone connections issue
    advertising->setMinPreferred(0x06);
    advertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();
  }

  void notifyStatus(std::bitset<8>& status) {
    Serial.print("Setting status to ");
    Serial.println(status.to_ulong(), BIN);
    uint8_t st = status.to_ulong();
    status_ch_->setValue(&st, 1);
    status_ch_->notify();
  }

  void notifyCookTime(uint32_t ms) { setTime(cook_ch_, ms); }

  void notifyIncubationTime(uint32_t ms) { setTime(incubation_ch_, ms); }

 private:
  BLEServer* server_;
  BLECharacteristic* status_ch_;
  BLECharacteristic* incubation_ch_;
  BLECharacteristic* cook_ch_;
  BLECharacteristic* cur_temps_ch_;
  BLECharacteristic* charts_ch_;

  void setTime(BLECharacteristic* ch, uint32_t ms_remaining) {
    ch->setValue(reinterpret_cast<uint8_t*>(&ms_remaining), sizeof(uint32_t));
    ch->notify();
  }
};
