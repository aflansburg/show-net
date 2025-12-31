//
//  AppDelegate.swift
//  ShowNet
//
//  Created by Abram Flansburg on 12/30/25.
//

@preconcurrency import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var animationTimer: Timer?
    private var animationFrameIndex = 0
    private let animationFrames = [
        "info.circle",
        "info.circle.fill"
    ]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set activation policy for menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Initial icon will be set by animation
            button.image = NSImage(systemSymbolName: animationFrames[0], accessibilityDescription: "Network Status")
        }

        // Create menu
        menu = NSMenu()

        updateNetworkStatus()

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshStatus), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu

        // Start icon animation
        startAnimation()
    }

    @objc func refreshStatus() {
        updateNetworkStatus()
    }

    @objc func copyIP(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }

        // Extract just the IP address
        let components = text.components(separatedBy: ": ")
        let ipToCopy = components.last ?? text

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ipToCopy, forType: .string)

        // Update menu item temporarily to show it was copied
        let originalTitle = sender.title
        sender.title = "✓ Copied!"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            sender.title = originalTitle
        }
    }

    @objc func quitApp() {
        animationTimer?.invalidate()
        NSApplication.shared.terminate(nil)
    }

    private func startAnimation() {
        // Update icon every 0.4 seconds for smooth pulsing effect
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.updateAnimationFrame()
        }
    }

    @objc private func updateAnimationFrame() {
        guard let button = statusItem.button else { return }

        // Cycle through animation frames
        let symbolName = animationFrames[animationFrameIndex]
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Network Status")

        // Move to next frame
        animationFrameIndex = (animationFrameIndex + 1) % animationFrames.count
    }

    private func updateNetworkStatus() {
        // Clear existing items (except separators and static items)
        while menu.items.count > 0 && menu.items[0].action != #selector(refreshStatus) {
            menu.removeItem(at: 0)
        }

        // Get network status
        let interfaces = getNetworkInterfaces()

        var index = 0

        // Add centered hint at the top
        let hintItem = NSMenuItem()
        let hintView = NSTextField(labelWithString: "💡 Click any IP to copy")
        hintView.font = NSFont.systemFont(ofSize: 11)
        hintView.textColor = .secondaryLabelColor
        hintView.alignment = .center
        hintItem.view = hintView
        menu.insertItem(hintItem, at: index)
        index += 1

        menu.insertItem(NSMenuItem.separator(), at: index)
        index += 1

        if interfaces.isEmpty {
            let item = NSMenuItem(title: "No active connections", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: index)
        } else {
            // Add local interfaces
            for interface in interfaces {
                let item = NSMenuItem(title: interface, action: #selector(copyIP(_:)), keyEquivalent: "")
                item.representedObject = interface // Store for copying
                menu.insertItem(item, at: index)
                index += 1
            }

            // Add separator
            menu.insertItem(NSMenuItem.separator(), at: index)
            index += 1

            // Add public IPv4 (loading placeholder)
            let publicIPItem = NSMenuItem(title: "Public IPv4: Loading...", action: #selector(copyIP(_:)), keyEquivalent: "")
            publicIPItem.isEnabled = false
            menu.insertItem(publicIPItem, at: index)
            index += 1

            // Add public IPv6 (loading placeholder)
            let publicIPv6Item = NSMenuItem(title: "Public IPv6: Loading...", action: #selector(copyIP(_:)), keyEquivalent: "")
            publicIPv6Item.isEnabled = false
            menu.insertItem(publicIPv6Item, at: index)

            // Fetch public IPv4 asynchronously
            fetchPublicIP { ip in
                DispatchQueue.main.async {
                    if let ip = ip {
                        publicIPItem.title = "Public IPv4: \(ip)"
                        publicIPItem.representedObject = "Public IPv4: \(ip)"
                        publicIPItem.isEnabled = true
                    } else {
                        publicIPItem.title = "Public IPv4: Unavailable"
                    }
                }
            }

            // Fetch public IPv6 asynchronously
            fetchPublicIPv6 { ip in
                DispatchQueue.main.async {
                    if let ip = ip {
                        publicIPv6Item.title = "Public IPv6: \(ip)"
                        publicIPv6Item.representedObject = "Public IPv6: \(ip)"
                        publicIPv6Item.isEnabled = true
                    } else {
                        publicIPv6Item.title = "Public IPv6: Unavailable"
                    }
                }
            }
        }

        // Icon animation continues regardless of connection status
        // The animation already indicates network monitoring is active
    }

    private func fetchPublicIP(completion: @escaping (String?) -> Void) {
        // Use curl to fetch public IPv4 - more reliable than DNS or URLSession
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            task.arguments = ["-s", "-4", "--max-time", "5", "https://ifconfig.me"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty,
                   self.isValidIPv4(output) {
                    completion(output)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
    }

    private func fetchPublicIPv6(completion: @escaping (String?) -> Void) {
        // Use curl to fetch public IPv6 - try IPv6-only endpoint
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            task.arguments = ["-s", "-6", "--max-time", "5", "https://ifconfig.me"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty,
                   self.isValidIPv6(output) {
                    completion(output)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
    }

    private func isValidIPv4(_ string: String) -> Bool {

        let components = string.components(separatedBy: ".")
        guard components.count == 4 else {
            return false
        }

        // Each component should be a number between 0-255
        return components.allSatisfy { component in
            guard let num = Int(component), num >= 0, num <= 255 else {
                return false
            }
            return true
        }
    }

    private func isValidIPv6(_ string: String) -> Bool {
        // Basic IPv6 validation: must contain colons, no angle brackets (rules out HTML),
        // reasonable length, and valid hex characters
        guard string.contains(":"),
              !string.contains("<"),
              !string.contains(">"),
              string.count < 50,  // IPv6 addresses are typically 39 chars max
              string.count > 2 else {
            return false
        }

        // Check if it matches basic IPv6 pattern (hex digits, colons, and optional dots for IPv4-mapped)
        let allowedChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.")
        return string.unicodeScalars.allSatisfy { allowedChars.contains($0) }
    }

    private func getNetworkInterfaces() -> [String] {
        var result: [String] = []

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {

                // Parse ifconfig output
                let lines = output.components(separatedBy: "\n")
                var currentInterfaceName: String?
                var ipv4Address: String?
                var ipv6Address: String?

                for line in lines {
                    if !line.hasPrefix("\t") && !line.hasPrefix(" ") && !line.isEmpty {
                        // New interface - save previous one if it had IPs
                        if let name = currentInterfaceName {
                            if let ipv4 = ipv4Address {
                                let entry = "\(name): \(ipv4)"
                                result.append(entry)
                            }
                            if let ipv6 = ipv6Address {
                                let entry = "\(name): \(ipv6)"
                                result.append(entry)
                            }
                        }

                        currentInterfaceName = parseInterfaceName(line)
                        ipv4Address = nil
                        ipv6Address = nil
                    } else if line.contains("inet ") && !line.contains("127.0.0.1") && !line.contains("inet6") {
                        // IPv4 address
                        if let ip = parseIPAddress(line, isIPv6: false) {
                            ipv4Address = ip
                        }
                    } else if line.contains("inet6") && !line.contains("::1") && !line.contains("fe80:") {
                        // IPv6 address (skip localhost and link-local)
                        if let ip = parseIPAddress(line, isIPv6: true) {
                            ipv6Address = ip
                        }
                    }
                }

                // Don't forget the last interface
                if let name = currentInterfaceName {
                    if let ipv4 = ipv4Address {
                        let entry = "\(name): \(ipv4)"
                        result.append(entry)
                    }
                    if let ipv6 = ipv6Address {
                        let entry = "\(name): \(ipv6)"
                        result.append(entry)
                    }
                }
            }
        } catch {
            result.append("Error reading network status")
        }

        return result
    }

    private func parseInterfaceName(_ line: String) -> String? {
        let components = line.components(separatedBy: ":")
        if let first = components.first {
            return first.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func parseIPAddress(_ line: String, isIPv6: Bool) -> String? {
        // Trim whitespace and split, filtering empty components
        let components = line.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }

        let keyword = isIPv6 ? "inet6" : "inet"
        if let inetIndex = components.firstIndex(of: keyword), inetIndex + 1 < components.count {
            var ip = components[inetIndex + 1]

            // For IPv6, remove the %interface suffix if present
            if isIPv6, let percentIndex = ip.firstIndex(of: "%") {
                ip = String(ip[..<percentIndex])
            }

            return ip
        }
        return nil
    }


    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

