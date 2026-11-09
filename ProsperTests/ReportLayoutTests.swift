import SwiftUI
import Testing
import UIKit
@testable import Prosper

/// DeviceActivityReport renders in another process and never reports its
/// height, so the app reserves one. These measure the real Today hero at every
/// text size it supports, on the narrowest supported iPhone, and check the
/// reservation covers it; a design change that grows the hero fails here
/// instead of clipping on someone's phone (UX-27).
@MainActor
struct ReportLayoutTests {
    /// iPhone SE width (375) minus the screen and card insets.
    static let heroWidth: CGFloat = 375 - 2 * 20 - 2 * 18

    static func heroHeight(at size: DynamicTypeSize) -> CGFloat {
        let view = TodayHeroReportView(snapshot: .sample)
            .environment(\.dynamicTypeSize, size)
            .frame(width: heroWidth)
            .fixedSize(horizontal: false, vertical: true)
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: heroWidth, height: .greatestFiniteMagnitude)).height
    }

    @Test("The reserved height covers the Today hero at every text size", arguments: DynamicTypeSize.allCases)
    func heroFits(size: DynamicTypeSize) {
        let needed = Self.heroHeight(at: size)
        let reserved = ReportLayout.heroHeight(for: size)
        #expect(needed <= reserved, "Hero needs \(needed)pt at \(size) but the app reserves \(reserved)pt")
    }

    @Test("Past the cap the hero stops growing")
    func heroIsCapped() {
        let atCap = Self.heroHeight(at: ReportLayout.heroMaxTypeSize)
        #expect(Self.heroHeight(at: .accessibility5) <= atCap + 1)
    }
}
