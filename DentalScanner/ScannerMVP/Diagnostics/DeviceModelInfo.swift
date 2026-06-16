import Foundation
import Darwin
import UIKit

struct DeviceModelInfo: Equatable {
    let identifier: String
    let marketingName: String

    static var current: DeviceModelInfo {
        let identifier = currentModelIdentifier()
        return DeviceModelInfo(
            identifier: identifier,
            marketingName: marketingName(for: identifier)
        )
    }

    private static func currentModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)

        let mirror = Mirror(reflecting: systemInfo.machine)
        let bytes = mirror.children.reduce(into: [UInt8]()) { partialResult, element in
            guard let value = element.value as? Int8,
                  value != 0
            else {
                return
            }

            partialResult.append(UInt8(bitPattern: value))
        }
        let identifier = String(bytes: bytes, encoding: .utf8) ?? ""

        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    private static func marketingName(for identifier: String) -> String {
        switch identifier {
        case "iPhone12,1":
            return "iPhone 11"
        case "iPhone12,3":
            return "iPhone 11 Pro"
        case "iPhone12,5":
            return "iPhone 11 Pro Max"
        case "iPhone14,5":
            return "iPhone 13"
        case "iPhone14,4":
            return "iPhone 13 mini"
        case "iPhone14,2":
            return "iPhone 13 Pro"
        case "iPhone14,3":
            return "iPhone 13 Pro Max"
        case "iPhone17,3":
            return "iPhone 16"
        case "iPhone17,4":
            return "iPhone 16 Plus"
        case "iPhone17,1":
            return "iPhone 16 Pro"
        case "iPhone17,2":
            return "iPhone 16 Pro Max"
        case "iPhone17,5":
            return "iPhone 16e"
        default:
            if identifier.hasPrefix("iPhone") {
                return "Unknown iPhone"
            }

            return identifier
        }
    }
}
