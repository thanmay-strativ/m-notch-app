// Ported from coucou (https://github.com/Louis-CFM/coucou), MIT License,
// Copyright (c) 2026 Louis Raillé. See LICENSES/coucou-MIT.txt.

import AppKit

/// Resting island size: the physical notch, or a small bar on screens without one.
public struct IslandScreenGeometry: Equatable {
    public static let fallbackNotchWidth: CGFloat = 184
    static let noNotchWidth: CGFloat = 80
    static let noNotchHeight: CGFloat = 24

    public let hasNotch: Bool
    public let width: CGFloat
    public let height: CGFloat

    public init(screenWidth: CGFloat, safeAreaTop: CGFloat, auxiliaryLeftWidth: CGFloat?,
                auxiliaryRightWidth: CGFloat?, menuBarHeight: CGFloat) {
        hasNotch = safeAreaTop > 0
        if hasNotch {
            if let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
                let measuredWidth = screenWidth - left - right
                width = measuredWidth > 0 && measuredWidth < screenWidth ? measuredWidth : Self.fallbackNotchWidth
            } else {
                width = Self.fallbackNotchWidth
            }
            height = safeAreaTop
        } else {
            width = Self.noNotchWidth
            height = min(Self.noNotchHeight, menuBarHeight)
        }
    }

    @MainActor
    public init(screen: NSScreen) {
        let visibleMenuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        self.init(screenWidth: screen.frame.width, safeAreaTop: screen.safeAreaInsets.top,
                  auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
                  auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
                  menuBarHeight: visibleMenuBarHeight > 0 ? visibleMenuBarHeight : NSStatusBar.system.thickness)
    }
}

/// Which screen the island lives on.
public enum IslandDisplayChoice: String, CaseIterable, Sendable {
    case followMouse, builtIn, main

    public var title: String {
        switch self {
        case .followMouse: return "Follow mouse"
        case .builtIn: return "Built-in screen"
        case .main: return "Main screen"
        }
    }

    @MainActor
    public func targetScreen(mouse: NSPoint = NSEvent.mouseLocation) -> NSScreen? {
        let screens = NSScreen.screens
        let builtIn = screens.first { $0.safeAreaInsets.top > 0 }
            ?? screens.first { CGDisplayIsBuiltin(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) != 0 }
        switch self {
        case .followMouse: return screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? screens.first
        case .builtIn: return builtIn ?? NSScreen.main ?? screens.first
        case .main: return screens.first ?? NSScreen.main
        }
    }
}
