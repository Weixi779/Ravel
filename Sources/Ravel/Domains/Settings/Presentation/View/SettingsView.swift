// Created by weixi on 2026/09/17.

import Localization
import SwiftUI

struct SettingsView: View {
    @Bindable var session: LogSession
    @Bindable var diffOptions: DiffViewOptions

    var body: some View {
        Form {
            Picker(I18n.historyPageSize, selection: Binding(
                get: { session.historyPageSize },
                set: { session.setHistoryPageSize($0) },
            )) {
                ForEach(LogSession.historyPageSizes, id: \.self) { size in
                    Text(size.formatted()).tag(size)
                }
            }
            Text(I18n.historyPageSizeHelp)
                .font(.callout)
                .foregroundStyle(.secondary)

            Section(I18n.historyTitle) {
                Picker(I18n.historyGraphStyle, selection: $session.graphStyle) {
                    Text(I18n.historyGraphStyleRounded)
                        .tag(HistoryGraphStyle.rounded)

                    Text(I18n.historyGraphStyleCurved)
                        .tag(HistoryGraphStyle.curved)
                }
            }

            Section {
                DiffReadingSettings(options: diffOptions)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DiffReadingSettings: View {
    @Bindable var options: DiffViewOptions
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Toggle(I18n.diffShowMarkers, isOn: Binding(
            get: { options.showsChangeMarkers ?? differentiateWithoutColor },
            set: { options.showsChangeMarkers = $0 },
        ))
        Button(I18n.diffMarkersFollowSystem) { options.showsChangeMarkers = nil }
            .disabled(options.showsChangeMarkers == nil)
    }
}
