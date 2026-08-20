import Cocoa
import Foundation

class SpaceIdentifier {
    
    let conn = _CGSDefaultConnection()
    let defaults = UserDefaults.standard
    
    typealias ScreenUUID = String

    private let allSpacesMask: Int32 = 0x7
    private let yabai = YabaiSpaceController()
    
    func getSpaceInfo() -> SpaceInfo {
        let nskey = NSDeviceDescriptionKey(rawValue:("NSScreenNumber"))
        guard let monitors = CGSCopyManagedDisplaySpaces(conn) as? [[String : Any]],
            let mainDisplay = NSScreen.main,
            let screenNumber = mainDisplay.deviceDescription[nskey] as? UInt32
        else { return SpaceInfo(keyboardFocusSpace: nil, activeSpaces: [], allSpaces: []) }
        
        let cfuuid = CGDisplayCreateUUIDFromDisplayID(screenNumber).takeRetainedValue()
        let screenUUID = CFUUIDCreateString(kCFAllocatorDefault, cfuuid) as String
        let yabaiData = yabai.spaceData()
        let occupiedSpaceIDs = yabaiData.occupiedSpaceIndices == nil
            ? getOccupiedSpaceIDs()
            : []
        let (activeSpaces, allSpaces) = parseSpaces(monitors: monitors,
                                                    occupiedSpaceIDs: occupiedSpaceIDs,
                                                    yabaiIndices: yabaiData.indicesByUUID,
                                                    yabaiOccupiedSpaceIndices: yabaiData.occupiedSpaceIndices)

        return SpaceInfo(keyboardFocusSpace: activeSpaces[screenUUID],
                         activeSpaces: activeSpaces.map{ $0.value },
                         allSpaces: allSpaces)
    }
    
    /* returns a mapping of screen uuids and their active space */
    private func parseSpaces(monitors: [[String : Any]],
                             occupiedSpaceIDs: Set<Int>,
                             yabaiIndices: [String: Int],
                             yabaiOccupiedSpaceIndices: Set<Int>?) -> ([ScreenUUID : Space], [Space]) {
        var activeSpaces: [ScreenUUID : Space] = [:]
        var allSpaces: [Space] = []
        var counter = 1
        var order = 0
        for m in monitors {
            guard let current = m["Current Space"] as? [String : Any],
                  let spaces = m["Spaces"] as? [[String : Any]],
                  let displayIdentifier = m["Display Identifier"] as? String
            else { continue }
            guard let id64 = current["id64"] as? Int,
                  let uuid = current["uuid"] as? String,
                  let type = current["type"] as? Int,
                  let managedSpaceId = current["ManagedSpaceID"] as? Int
            else { continue }

            allSpaces += parseSpaceList(spaces: spaces,
                                        startIndex: counter,
                                        activeUUID: uuid,
                                        displayUUID: displayIdentifier,
                                        occupiedSpaceIDs: occupiedSpaceIDs,
                                        yabaiIndices: yabaiIndices,
                                        yabaiOccupiedSpaceIndices: yabaiOccupiedSpaceIndices)
            
            let filterFullscreen = spaces.filter{ $0["TileLayoutManager"] as? [String : Any] == nil}
            let target = filterFullscreen.enumerated().first(where: { $1["uuid"] as? String == uuid})
            let fallbackNumber = target == nil ? nil : target!.offset + counter
            let number = yabaiIndices[uuid] ?? fallbackNumber
            
            activeSpaces[displayIdentifier] = Space(id64: id64,
                                                    uuid: uuid,
                                                    type: type,
                                                    managedSpaceId: managedSpaceId,
                                                    displayUUID: displayIdentifier,
                                                    number: number,
                                                    order: order,
                                                    isActive: true,
                                                    hasApplicationWindows: hasApplicationWindows(
                                                        managedSpaceId: managedSpaceId,
                                                        spaceIndex: number,
                                                        cgOccupiedSpaceIDs: occupiedSpaceIDs,
                                                        yabaiOccupiedSpaceIndices: yabaiOccupiedSpaceIndices))
            counter += filterFullscreen.count
            order += 1
        }
        allSpaces.sort {
            if let left = $0.number, let right = $1.number {
                return left < right
            }
            return $0.number != nil
        }
        return (activeSpaces, allSpaces)
    }
    
    private func parseSpaceList(spaces: [[String : Any]],
                                startIndex: Int,
                                activeUUID: String,
                                displayUUID: String,
                                occupiedSpaceIDs: Set<Int>,
                                yabaiIndices: [String: Int],
                                yabaiOccupiedSpaceIndices: Set<Int>?) -> [Space] {
        var ret: [Space] = []
        var counter: Int = startIndex
        for s in spaces {
            guard let id64 = s["id64"] as? Int,
                  let uuid = s["uuid"] as? String,
                  let type = s["type"] as? Int,
                  let managedSpaceId = s["ManagedSpaceID"] as? Int
                  else { continue }
            let isFullscreen = s["TileLayoutManager"] as? [String : Any] == nil ? false : true
            let fallbackNumber: Int? = isFullscreen ? nil : counter
            let number = yabaiIndices[uuid] ?? fallbackNumber
            ret.append(
                Space(id64: id64,
                      uuid: uuid,
                      type: type,
                      managedSpaceId: managedSpaceId,
                      displayUUID: displayUUID,
                      number: number,
                      order: 0,
                      isActive: uuid == activeUUID,
                      hasApplicationWindows: hasApplicationWindows(
                          managedSpaceId: managedSpaceId,
                          spaceIndex: number,
                          cgOccupiedSpaceIDs: occupiedSpaceIDs,
                          yabaiOccupiedSpaceIndices: yabaiOccupiedSpaceIndices)))
            if !isFullscreen {
                counter += 1
            }
        }
        return ret
    }

    private func hasApplicationWindows(managedSpaceId: Int,
                                       spaceIndex: Int?,
                                       cgOccupiedSpaceIDs: Set<Int>,
                                       yabaiOccupiedSpaceIndices: Set<Int>?) -> Bool {
        if let occupiedIndices = yabaiOccupiedSpaceIndices,
           let index = spaceIndex {
            return occupiedIndices.contains(index)
        }
        return cgOccupiedSpaceIDs.contains(managedSpaceId)
    }

    /* Returns the managed space IDs containing normal application windows. */
    private func getOccupiedSpaceIDs() -> Set<Int> {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        let windowIDs: [NSNumber] = windows.compactMap { window in
            guard let windowID = window[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber,
                  layer.intValue == 0,
                  alpha.doubleValue > 0,
                  isRegularApplication(pid: ownerPID.int32Value),
                  hasVisibleSize(window: window)
            else { return nil }
            return windowID
        }

        guard !windowIDs.isEmpty,
              let spaceIDs = CGSCopySpacesForWindows(conn,
                                                     allSpacesMask,
                                                     windowIDs as CFArray) as? [NSNumber]
        else { return [] }

        return Set(spaceIDs.map { $0.intValue })
    }

    private func isRegularApplication(pid: pid_t) -> Bool {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid)
        else { return false }
        return app.activationPolicy == .regular
    }

    private func hasVisibleSize(window: [String: Any]) -> Bool {
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? NSNumber,
              let height = bounds["Height"] as? NSNumber
        else { return false }
        return width.doubleValue > 1 && height.doubleValue > 1
    }
}

struct YabaiSpaceData {
    let indicesByUUID: [String: Int]
    let occupiedSpaceIndices: Set<Int>?
}

final class YabaiSpaceController {
    private static let executablePath: String? = {
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/yabai" }
        let commonPaths = [
            "/opt/homebrew/bin/yabai",
            "/usr/local/bin/yabai",
            "/run/current-system/sw/bin/yabai"
        ]
        return (environmentPaths + commonPaths).first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }()

    @discardableResult
    func switchTo(space: Space) -> Bool {
        guard let index = space.number else { return false }
        return run(arguments: ["-m", "space", "--focus", String(index)]).status == 0
    }

    func spaceData() -> YabaiSpaceData {
        let spacesResult = run(arguments: ["-m", "query", "--spaces"], captureOutput: true)
        guard spacesResult.status == 0,
              let spacesData = spacesResult.output,
              let spaceRecords = try? JSONSerialization.jsonObject(with: spacesData) as? [[String: Any]]
        else { return YabaiSpaceData(indicesByUUID: [:], occupiedSpaceIndices: nil) }

        var indices: [String: Int] = [:]
        for record in spaceRecords {
            guard let uuid = record["uuid"] as? String,
                  let index = record["index"] as? NSNumber
            else { continue }
            indices[uuid] = index.intValue
        }

        let windowsResult = run(arguments: ["-m", "query", "--windows"], captureOutput: true)
        guard windowsResult.status == 0,
              let windowsData = windowsResult.output,
              let windowRecords = try? JSONSerialization.jsonObject(with: windowsData) as? [[String: Any]]
        else { return YabaiSpaceData(indicesByUUID: indices, occupiedSpaceIndices: nil) }

        let occupiedIndices = Set(windowRecords.compactMap { window -> Int? in
            guard !isGhostWindow(window),
                  let space = window["space"] as? NSNumber,
                  space.intValue > 0
            else { return nil }
            return space.intValue
        })
        return YabaiSpaceData(indicesByUUID: indices,
                              occupiedSpaceIndices: occupiedIndices)
    }

    private func isGhostWindow(_ window: [String: Any]) -> Bool {
        let hasAXReference = (window["has-ax-reference"] as? NSNumber)?.boolValue ?? false
        let role = window["role"] as? String ?? ""
        let subrole = window["subrole"] as? String ?? ""
        let canMove = (window["can-move"] as? NSNumber)?.boolValue ?? false
        let canResize = (window["can-resize"] as? NSNumber)?.boolValue ?? false
        let isNativeFullscreen = (window["is-native-fullscreen"] as? NSNumber)?.boolValue ?? false

        return !isNativeFullscreen
            && !hasAXReference
            && role.isEmpty
            && subrole.isEmpty
            && !canMove
            && !canResize
    }

    private func run(arguments: [String],
                     captureOutput: Bool = false) -> (status: Int32, output: Data?) {
        guard let executablePath = YabaiSpaceController.executablePath else {
            return (-1, nil)
        }

        let task = Process()
        task.launchPath = executablePath
        task.arguments = arguments

        let outputPipe = captureOutput ? Pipe() : nil
        task.standardOutput = outputPipe ?? FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.launch()

        let output = outputPipe?.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, output)
    }
}
