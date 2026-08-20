import Foundation

struct Space {
    let id64: Int
    let uuid: String
    let type: Int
    let managedSpaceId: Int
    let displayUUID: String
    let number: Int?            // fullscreen apps don't have a number
    let order: Int              // spaces are in order including fullscreen apps
    let isActive: Bool          // space is currently visible on the monitor
    let hasApplicationWindows: Bool
}
