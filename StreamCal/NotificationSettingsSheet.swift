import SwiftUI
import SwiftData
import UserNotifications

struct NotificationSettingsSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Query private var shows: [Show]
    @Query private var teams: [SportTeam]

    @AppStorage("airReminderHour") private var airReminderHour: Int = 9
    @AppStorage("weeklySummaryEnabled") private var weeklySummaryEnabled: Bool = true
    @AppStorage("weeklySummaryHour") private var weeklySummaryHour: Int = 20
    @AppStorage("gameReminderMinutesBefore") private var gameReminderMinutesBefore: Int = 120
    @AppStorage("advanceReminderEnabled") private var advanceReminderEnabled: Bool = false

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private enum TimeSlot { case air, weekly }
    @State private var editingSlot: TimeSlot? = nil
    @State private var pickerDate: Date = .now

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    switch notificationStatus {
                    case .authorized:
                        Section("Episode Reminders") {
                            Label("Notifications enabled", systemImage: "bell.fill")
                                .foregroundStyle(.green)

                            timeRow(label: "New episode reminder", hour: airReminderHour) {
                                pickerDate = dateFromHour(airReminderHour)
                                editingSlot = .air
                            }

                            Toggle("24-hour advance reminder", isOn: $advanceReminderEnabled)
                                .onChange(of: advanceReminderEnabled) { _, _ in rescheduleShowNotifications() }

                            Toggle("Weekly summary", isOn: $weeklySummaryEnabled)
                                .onChange(of: weeklySummaryEnabled) { _, _ in rescheduleShowNotifications() }

                            if weeklySummaryEnabled {
                                timeRow(label: "Sunday summary time", hour: weeklySummaryHour) {
                                    pickerDate = dateFromHour(weeklySummaryHour)
                                    editingSlot = .weekly
                                }
                            }
                        }

                        Section("Sports Reminders") {
                            Picker("Game reminder", selection: $gameReminderMinutesBefore) {
                                Text("15 min before").tag(15)
                                Text("30 min before").tag(30)
                                Text("1 hour before").tag(60)
                                Text("2 hours before").tag(120)
                            }
                            .onChange(of: gameReminderMinutesBefore) { _, _ in rescheduleTeamNotifications() }
                        }

                    case .denied:
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Notifications disabled", systemImage: "bell.slash")
                                    .foregroundStyle(.orange)
                                Text("Enable notifications in iOS Settings to get episode reminders.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .font(.caption)
                            }
                        }

                    case .notDetermined:
                        Section {
                            Button("Enable Notifications") {
                                Task {
                                    await NotificationService.shared.requestPermission()
                                    notificationStatus = await NotificationService.shared.authorizationStatus()
                                }
                            }
                        }

                    default:
                        Section {
                            Label("Unknown status", systemImage: "bell")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(editingSlot != nil)

                if let slot = editingSlot {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { editingSlot = nil }

                    VStack(spacing: 16) {
                        Text(slotTitle(slot))
                            .font(.title3.weight(.semibold))

                        DatePicker("", selection: $pickerDate, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()

                        HStack(spacing: 12) {
                            Button("Cancel") { editingSlot = nil }
                                .frame(maxWidth: .infinity)
                                .buttonStyle(.bordered)
                            Button("Done") {
                                let hour = Calendar.current.component(.hour, from: pickerDate)
                                switch slot {
                                case .air: airReminderHour = hour
                                case .weekly: weeklySummaryHour = hour
                                }
                                rescheduleShowNotifications()
                                editingSlot = nil
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.modal, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    .padding(.horizontal, 32)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                notificationStatus = await NotificationService.shared.authorizationStatus()
            }
            .animation(.spring(duration: 0.3), value: editingSlot == nil)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func timeRow(label: String, hour: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Text(formattedHour(hour))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func slotTitle(_ slot: TimeSlot) -> String {
        switch slot {
        case .air: return "New Episode Reminder"
        case .weekly: return "Weekly Summary"
        }
    }

    private func dateFromHour(_ hour: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func formattedHour(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour().minute())
    }

    private func rescheduleShowNotifications() {
        Task { await NotificationService.shared.scheduleNotifications(for: shows) }
    }

    private func rescheduleTeamNotifications() {
        Task {
            for team in teams {
                await NotificationService.shared.scheduleNotifications(for: team)
            }
        }
    }
}
