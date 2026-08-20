import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, ReloadDelegate {
    
    let spaceIdentifier = SpaceIdentifier()
    let observer = Observer()
    let statusItem = StatusItem()
    private var updateWorkItem: DispatchWorkItem?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UserDefaults.standard.register(defaults: [
            Preference.icon: Preference.Icon.perSpace.rawValue,
            Preference.color: Preference.Color.whiteOnBlack.rawValue,
            Preference.maxIndexCount: 10
        ])
        PFMoveToApplicationsFolderIfNecessary ()
        statusItem.delegate = self
        NSApp.setActivationPolicy(.accessory)
        observer.setupObservers(using: updateSpaceNumber)
        setLoginItem()
        statusItem.createMenu()
        updateSpaceNumber(())
    }
    
    func reload() {
        observer.setupObservers(using: updateSpaceNumber)
        setLoginItem()
        statusItem.createMenu()
        updateSpaceNumber(())
    }

    func refresh() {
        updateSpaceNumber(())
    }
    
    private func updateSpaceNumber(_ : Any) {
        updateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let info = self.spaceIdentifier.getSpaceInfo()
            self.statusItem.updateMenuImage(spaceInfo: info)
        }
        updateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10), execute: workItem)
    }
    
    private func setLoginItem() {
        let b = UserDefaults.standard.bool(forKey: Preference.App.launchOnLogin.rawValue)
        let path = Bundle.main.bundlePath
        let add = "tell application \"System Events\" to make login item at end with properties {name: \"SpaceId\",path:\"\(path)\", hidden:true}"
        let remove = "tell application \"System Events\" to delete login item \"SpaceId\""
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = b ? ["-e", add] : ["-e", remove]
        task.launch()
    }
}

protocol ReloadDelegate {
    func reload()
    func refresh()
}
