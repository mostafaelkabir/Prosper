import SwiftUI
import UserNotifications

/// Settings ▸ Nightly check-in (E10.1): whether to be asked, when, and how the
/// question is put.
struct NightlyCheckInSettingsView: View {
    @ObservedObject private var center = NightlyCheckInCenter.shared
    @State private var notificationStatus: UNAuthorizationStatus?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var enabled: Binding<Bool> {
        Binding(get: { center.isEnabled }, set: { center.setEnabled($0) })
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: center.reminderMinute / 60,
                    minute: center.reminderMinute % 60,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                center.setReminderMinute((parts.hour ?? 22) * 60 + (parts.minute ?? 0))
            }
        )
    }

    private var prompt: Binding<String> {
        Binding(get: { center.prompt.id }, set: { center.setPrompt(CheckInPrompt.with(id: $0)) })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Ask me every night", isOn: enabled)
                if center.isEnabled {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("One notification before you sleep, with two buttons: I won, or Not today. Answer from the lock screen, or on Today from 6 PM. A night you miss waits on Today until you answer it.")
            }

            if center.isEnabled {
                Section {
                    Picker("Question", selection: prompt) {
                        ForEach(CheckInPrompt.all) { prompt in
                            Text(prompt.question).tag(prompt.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("The question")
                } footer: {
                    Text("It never names anything more specific. You know what you're answering; anyone glancing at your lock screen doesn't.")
                }

                notificationsSection
            }

            Section {
                LabeledContent("Current streak", value: nights(center.history.currentStreak(now: .now)))
                LabeledContent("Best streak", value: nights(center.history.bestStreak))
                LabeledContent("Nights won", value: "\(center.history.totalWins)")
            } header: {
                Text("Your record")
            } footer: {
                Text("A night that went wrong ends the streak, not the record. Answers stay on this iPhone.")
            }
        }
        .navigationTitle("Nightly check-in")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNotificationStatus() } }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        switch notificationStatus {
        case .denied:
            Section {
                Label("Notifications are off, so the question can't reach you. It still waits on Today.", systemImage: "bell.slash.fill")
                    .foregroundStyle(.orange)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        case .notDetermined:
            Section {
                Button("Turn on notifications") {
                    Task {
                        _ = await NotificationService.shared.requestPermission()
                        await refreshNotificationStatus()
                        center.refreshReminders()
                    }
                }
            } footer: {
                Text("Without them the question only waits on Today.")
            }
        default:
            EmptyView()
        }
    }

    private func nights(_ count: Int) -> String {
        count == 1 ? "1 night" : "\(count) nights"
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.shared.authorizationStatus()
    }
}
