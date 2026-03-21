import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var shows: [Show]
    @Query private var episodes: [Episode]

    @State private var showingDeleteAllConfirm = false
    @State private var showingDeletedBanner = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    // Notification time picker modal
    private enum TimeSlot { case air, weekly }
    @State private var editingSlot: TimeSlot? = nil
    @State private var pickerDate: Date = .now

    @AppStorage("airReminderHour") private var airReminderHour: Int = 9
    @AppStorage("weeklySummaryEnabled") private var weeklySummaryEnabled: Bool = true
    @AppStorage("weeklySummaryHour") private var weeklySummaryHour: Int = 20

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                Section("About") {
                    LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")
                    LabeledContent("Shows", value: "\(shows.count)")
                    LabeledContent("Episodes", value: "\(episodes.count)")
                }

                Section("Notifications") {
                    switch notificationStatus {
                    case .authorized:
                        Label("Enabled", systemImage: "bell.fill")
                            .foregroundStyle(.green)

                        timeRow(label: "New episode reminder", hour: airReminderHour) {
                            pickerDate = dateFromHour(airReminderHour)
                            editingSlot = .air
                        }

                        Toggle("Weekly summary", isOn: $weeklySummaryEnabled)
                            .onChange(of: weeklySummaryEnabled) { _, _ in rescheduleNotifications() }

                        if weeklySummaryEnabled {
                            timeRow(label: "Sunday summary time", hour: weeklySummaryHour) {
                                pickerDate = dateFromHour(weeklySummaryHour)
                                editingSlot = .weekly
                            }
                        }

                    case .denied:
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Disabled", systemImage: "bell.slash")
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
                    case .notDetermined:
                        Button("Enable Episode Notifications") {
                            Task {
                                await NotificationService.shared.requestPermission()
                                notificationStatus = await NotificationService.shared.authorizationStatus()
                            }
                        }
                    default:
                        Label("Unknown", systemImage: "bell")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data") {
                    Button("Delete All Data", role: .destructive) {
                        showingDeleteAllConfirm = true
                    }
                }
                }
                .disabled(showingDeleteAllConfirm || editingSlot != nil)

                if showingDeleteAllConfirm {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    VStack(spacing: 16) {
                        Text("Delete All Data?")
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)

                        Text("This will permanently delete all \(shows.count) shows and \(episodes.count) episodes. This cannot be undone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        VStack(spacing: 8) {
                            Button(role: .destructive) {
                                showingDeleteAllConfirm = false
                                deleteAllData()
                            } label: {
                                Text("Delete All Data")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)

                            Button("Cancel") {
                                showingDeleteAllConfirm = false
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    .padding(.horizontal, 32)
                    .transition(.scale.combined(with: .opacity))
                }

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
                            Button("Cancel") {
                                editingSlot = nil
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)

                            Button("Done") {
                                let hour = Calendar.current.component(.hour, from: pickerDate)
                                switch slot {
                                case .air: airReminderHour = hour
                                case .weekly: weeklySummaryHour = hour
                                }
                                rescheduleNotifications()
                                editingSlot = nil
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    .padding(.horizontal, 32)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .navigationTitle("Settings")
            .task {
                notificationStatus = await NotificationService.shared.authorizationStatus()
            }
            // Success banner overlaid at the top
            .overlay(alignment: .top) {
                if showingDeletedBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All data deleted")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: showingDeletedBanner)
            .animation(.spring(duration: 0.3), value: showingDeleteAllConfirm)
            .animation(.spring(duration: 0.3), value: editingSlot == nil)
        }
    }

    // MARK: - Row helper

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

    // MARK: - Helpers

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

    private func rescheduleNotifications() {
        Task {
            await NotificationService.shared.scheduleNotifications(for: shows)
        }
    }

    private func deleteAllData() {
        do {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

            // Delete Shows only — Episodes are cascade-deleted automatically
            // via the @Relationship(deleteRule: .cascade) on Show.episodes.
            // Trying to batch-delete Episodes first triggers a SwiftData OTO
            // constraint violation on the Episode.show inverse relationship.
            try modelContext.delete(model: Show.self)
            try modelContext.save()

            showingDeletedBanner = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                showingDeletedBanner = false
            }
        } catch {
            // Settings delete errors are non-fatal; banner won't show but data may be partially cleared
        }
    }

}

#Preview {
    SettingsView()
        .modelContainer(for: [Show.self, Episode.self], inMemory: true)
}
