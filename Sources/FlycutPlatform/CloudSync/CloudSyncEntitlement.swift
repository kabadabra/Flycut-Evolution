import Foundation
import Security

enum CloudSyncEntitlement {
    static func available() -> Bool {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault) else { return false }
        let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String]
        let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
        let environment = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-environment" as CFString, nil) as? String
        return services?.contains("CloudKit") == true &&
            containers?.contains("iCloud.com.edynamics.flycut") == true && environment == "Production"
    }
}
