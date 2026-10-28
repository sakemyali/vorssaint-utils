// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The production reading, without the account service or an open island.
/// Accessibility frames also catch a full label attached to a shorter fallback.
enum NotchAgentLimitReadingTests {
    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated { checks(suite) }
    }

    @MainActor private static func checks(_ suite: TestSuite) {
        _ = NSApplication.shared
        // SwiftUI creates accessibility nodes lazily. Enable them only in
        // this process and restore the previous value when the checks end.
        let attribute = "AXEnhancedUserInterface"
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: attribute)?.takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: attribute)
        defer { NSApp.perform(setter, with: previous, with: attribute) }
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 223, height: 24),
                              styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchAgents(language)
            let locale = language.formattingLocale()
            for display in NotchAgentLimitDisplay.allCases {
                let limit = AgentLimitWindow(id: "reading", kind: .weekly, minutes: 10_080, scope: "Sonnet",
                                             usedPercent: display == .remaining ? 0 : 100, resetsAt: nil)
                let share = NotchAgentSupport.limitShare(limit, display: display, text: text)
                let full = NSHostingView(rootView: Text(share)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().fixedSize())
                let required = full.fittingSize.width
                for width: CGFloat in [183, 223] {
                    for title in [text.session, "\(text.weekly) · Sonnet"] {
                        for countdown in [nil, AgentFormat.duration(6 * 86_400 + 23 * 3600, locale: locale),
                                          "≈ " + AgentFormat.duration(4 * 3600 + 59 * 60, locale: locale)] {
                            let host = NSHostingView(rootView: NotchAgentLimitReading(
                                title: title, share: share, countdown: countdown, tint: .white)
                                .environment(\.locale, locale).frame(width: width, height: 24))
                            window.contentView = host
                            window.setContentSize(CGSize(width: width, height: 24))
                            settle(host)
                            let readings = elements(host)
                                .filter { $0.accessibilityIdentifier?() == "notch.agentLimitShare" }
                            let context = "\(language.rawValue), \(width) pt, \(title), \(share), reset \(countdown ?? "none")"
                            suite.expect(readings.count == 1, "one visible limit reading: \(context)")
                            guard let reading = readings.first else { continue }
                            let value = reading.accessibilityValue?() as? String ?? reading.accessibilityLabel?()
                            suite.expect(value == share, "the visible limit names remaining or used: \(context)")
                            let frame = reading.accessibilityFrame?() ?? .zero
                            let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
                            suite.expect(frame.width >= required - 1 && frame.minX >= bounds.minX - 1
                                         && frame.maxX <= bounds.maxX + 1 && frame.height > 0,
                                         "the whole worded limit stays inside its card: \(context)")
                        }
                    }
                }
            }
        }
        for (width, showsCountdown): (CGFloat, Bool) in [(183, false), (320, true)] {
            let host = NSHostingView(rootView: NotchAgentLimitReading(
                title: "Week · Sonnet", share: "100% used", countdown: "≈ 6d 23h", tint: .white)
                .frame(width: width, height: 24))
            window.contentView = host
            window.setContentSize(CGSize(width: width, height: 24))
            settle(host)
            let countdown = elements(host)
                .filter { $0.accessibilityIdentifier?() == "notch.agentLimitCountdown" }
            suite.expect(countdown.isEmpty != showsCountdown,
                         "a reset countdown gives way only when the complete reading needs its room at \(width) pt")
        }
    }

    @MainActor private static func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
    }

    // SwiftUI's nodes expose the selectors without inheriting from
    // NSAccessibilityElement or declaring NSAccessibilityProtocol.
    @MainActor private static func elements(_ element: AnyObject) -> [AnyObject] {
        [element] + (element.accessibilityChildren?() ?? []).flatMap { elements($0 as AnyObject) }
    }
}
