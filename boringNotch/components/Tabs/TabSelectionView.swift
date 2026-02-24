//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
    /// Optional Defaults key — tab is hidden when the setting is false
    let settingsKey: Defaults.Key<Bool>?

    init(label: String, icon: String, view: NotchViews, settingsKey: Defaults.Key<Bool>? = nil) {
        self.label = label
        self.icon = icon
        self.view = view
        self.settingsKey = settingsKey
    }
}

let allTabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Time", icon: "timer", view: .timeTracking, settingsKey: .showTimeTracking),
    TabModel(label: "Team", icon: "person.2.fill", view: .team),
    TabModel(label: "VPN", icon: "shield.lefthalf.filled", view: .vpn),
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.showTimeTracking) var showTimeTracking
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        allTabs.filter { tab in
            guard let key = tab.settingsKey else { return true }
            return Defaults[key]
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
