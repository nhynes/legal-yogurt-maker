import CoreBluetooth
import UIKit
import UserNotifications

let SERVICE_UUID = CBUUID(string: "864ca7a0-268c-4224-96d3-1982825571f0")
let STATUS_CH = CBUUID(string: "864ca7a1-268c-4224-96d3-1982825571f0")
let COOK_TIME_CH = CBUUID(string: "864ca7a2-268c-4224-96d3-1982825571f0")
let INCUBATION_TIME_CH = CBUUID(string: "864ca7a3-268c-4224-96d3-1982825571f0")
let TEMPS_CH = CBUUID(string: "864ca7a4-268c-4224-96d3-1982825571f0")
let CHARTS_CH = CBUUID(string: "864ca7a5-268c-4224-96d3-1982825571f0")

struct StatusOptions: OptionSet {
    let rawValue: UInt8

    static let running = StatusOptions(rawValue: 1 << 0)
    static let cooking = StatusOptions(rawValue: 1 << 1)
    static let cooling = StatusOptions(rawValue: 1 << 2)
    static let incubating = StatusOptions(rawValue: 1 << 3)
}

class ViewController: UIViewController {
    // MARK: Properties

    var statusLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 48))
    var timerLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 48))
    var actionButton = UIButton(type: .system)
    var playImage = UIImage(contentsOfFile: Bundle.main.path(forResource: "circled-play", ofType: "png")!)
    var pauseImage = UIImage(contentsOfFile: Bundle.main.path(forResource: "circled-pause", ofType: "png")!)

    var centralManager: CBCentralManager!
    var device: CBPeripheral!

    var statusCh: CBCharacteristic!
    var cookTimeCh: CBCharacteristic!
    var incubationTimeCh: CBCharacteristic!
    var tempsCh: CBCharacteristic!
    var chartsCh: CBCharacteristic!

    var status = StatusOptions(rawValue: 0)
    var cookTime: UInt32 = 0 // ms
    var incubationTime: UInt32 = 0 // ms
    var outerTemp: UInt8 = 0 // degrees C
    var innerTemp: UInt8 = 0 // degrees C

    var timeFormatter = DateComponentsFormatter()

    let conenctingModal = UIAlertController(title: nil, message: "Connecting to device\n\n\n", preferredStyle: .alert)

    func showConnectingSpinner() {
        present(conenctingModal, animated: true, completion: nil)
    }

    func hideConnectingSpinner() {
        dismiss(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let spinner: UIActivityIndicatorView = UIActivityIndicatorView(style: UIActivityIndicatorView.Style.whiteLarge)
        spinner.frame = conenctingModal.view.frame.offsetBy(dx: 0, dy: spinner.frame.height / 2)
        spinner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        spinner.color = UIColor.black
        spinner.startAnimating()
        conenctingModal.view.addSubview(spinner)

        statusLabel.center = CGPoint(x: view.center.x, y: view.frame.height / 5)
        statusLabel.textAlignment = .center
        statusLabel.font = statusLabel.font.withSize(36)
        view.addSubview(statusLabel)

        timerLabel.center = CGPoint(x: view.center.x, y: statusLabel.frame.maxY + 32)
        timerLabel.textAlignment = .center
        timerLabel.font = statusLabel.font.withSize(42)
        view.addSubview(timerLabel)

        actionButton.tintColor = .black
        actionButton.frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        actionButton.center = CGPoint(x: view.center.x, y: view.frame.height * 4 / 5)
        actionButton.setImage(playImage, for: .normal)
        actionButton.addTarget(self, action: #selector(toggleDevice), for: .touchUpInside)
        view.addSubview(actionButton)

        timeFormatter.unitsStyle = .positional
        timeFormatter.includesApproximationPhrase = false
        timeFormatter.includesTimeRemainingPhrase = false
        timeFormatter.allowedUnits = [.hour, .minute, .second]

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        startManager()
    }

    @objc private func toggleDevice() {
        if status.contains(.running) {
            status.remove(.running)
        } else {
            status.insert(.running)
        }
        updateStatus()
        updateStatusText()
        updateActionButton()
    }

    private func updateStatus() {
        guard let ch = statusCh else {
            return
        }
        if status.contains(.running), status.subtracting(.running).isEmpty {
            status.insert(.cooking)
        }
        device.writeValue(withUnsafeBytes(of: status.rawValue) { Data($0) }, for: ch, type: .withResponse)
    }

    private func updateActionButton() {
        if status.contains(.running) {
            actionButton.setImage(pauseImage, for: .normal)
        } else {
            actionButton.setImage(playImage, for: .normal)
        }
    }

    private func startManager() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func updateStatusText() {
        var statusText: String
        if status.contains(.cooking) {
            statusText = "Cooking"
        } else if status.contains(.cooling) {
            statusText = "Cooling"
            timerLabel.text = ""
        } else if status.contains(.incubating) {
            statusText = "Incubating"
        } else {
            statusText = "Idle"
            timerLabel.text = ""
        }
//        statusText += "\n"
//        if !status.isEmpty && !status.contains(.running) {
//            statusText += "(Paused)"
//        }
        statusLabel.text = statusText
    }
}

// MARK: - CBCentralManagerDelegate

extension ViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            showConnectingSpinner()
            centralManager?.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        device = peripheral
        device.delegate = self
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        centralManager.stopScan()
        device.discoverServices([SERVICE_UUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        device = nil
        startManager()
    }
}

// MARK: - CBPeripheralDelegate

extension ViewController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let service = peripheral.services?[0]
        peripheral.discoverCharacteristics(nil, for: service!)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for ch in service.characteristics! {
            switch ch.uuid {
            case STATUS_CH:
                statusCh = ch
            case COOK_TIME_CH:
                cookTimeCh = ch
            case INCUBATION_TIME_CH:
                incubationTimeCh = ch
            case TEMPS_CH:
                tempsCh = ch
            case CHARTS_CH:
                chartsCh = ch
            default:
                ()
            }
            peripheral.setNotifyValue(true, for: ch)
        }
        hideConnectingSpinner()
        peripheral.readValue(for: statusCh)
        peripheral.readValue(for: cookTimeCh)
        peripheral.readValue(for: incubationTimeCh)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        switch characteristic {
        case statusCh:
            status = StatusOptions(rawValue: characteristic.value!.first ?? 0)
            if status.contains(.incubating) {
                let notification = UNMutableNotificationContent()
                notification.title = "Milk is done cooking"
                notification.body = "Time to add the starter culture!"
                let request = UNNotificationRequest(identifier: "proyo_notif",
                                                    content: notification,
                                                    trigger: nil)
                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
            }
            updateStatusText()
            updateActionButton()

        case cookTimeCh:
            cookTime = characteristic.value!.withUnsafeBytes {
                $0.load(as: UInt32.self)
            }
            if status.contains(.cooking) {
                timerLabel.text = timeFormatter.string(from: Double(cookTime) / 1000.0)
            }

        case incubationTimeCh:
            let val = characteristic.value!
            if val.isEmpty {
                incubationTime = 0
            } else {
                incubationTime = val.withUnsafeBytes {
                    $0.load(as: UInt32.self)
                }
                if status.contains(.incubating) {
                    timerLabel.text = timeFormatter.string(from: Double(incubationTime) / 1000.0)
                }
            }

        case tempsCh:
            let val = characteristic.value!
            innerTemp = val[0]
            outerTemp = val[1]
            print("temps", innerTemp, outerTemp)

        default:
            ()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if error != nil {
            print("ERROR WRITING CH")
        }
    }
}
