import SwiftUI
import TerminalAssetDomain

/// The "New Event" sheet: a standard grouped form, like the one in Apple Calendar.
struct AddEventView: View {
    @Bindable var model: AddEventViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Describe it, like “lunch tomorrow 12:30”", text: $model.quickText)
                        .submitLabel(.go)
                        .onSubmit { model.applyQuickText() }
                } header: {
                    Text("Quick add")
                } footer: {
                    Text(model.understood.isEmpty ? "Read on this device. Nothing is sent anywhere." : model.understood)
                }

                Section {
                    TextField("Title", text: $model.draft.title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                    TextField("Location", text: $model.draft.location)
                }

                Section {
                    Toggle("All-day", isOn: $model.draft.isAllDay)
                    DatePicker("Starts", selection: startBinding, displayedComponents: components)
                    DatePicker("Ends", selection: $model.draft.end, in: model.endRange, displayedComponents: components)
                }

                if model.calendars.count > 1 {
                    Section {
                        Picker("Calendar", selection: $model.draft.calendarID) {
                            ForEach(model.calendars) { calendar in
                                Text(calendar.title).tag(Optional(calendar.id))
                            }
                        }
                    }
                }

                if let message = model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { if await model.save() { dismiss() } }
                    }
                    .disabled(!model.canSave)
                }
            }
            .task { await model.loadCalendars() }
            .task {
                guard autofocus else { return }
                // Focusing while the sheet is still sliding up is ignored, so wait for it to settle.
                try? await Task.sleep(for: .milliseconds(350))
                titleFocused = true
            }
        }
        .interactiveDismissDisabled(model.isSaving)
    }

    private var components: DatePickerComponents {
        model.draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// Moving the start drags the end along, as in Apple Calendar.
    private var startBinding: Binding<Date> {
        Binding(
            get: { model.draft.start },
            set: { model.draft.moveStart(to: $0) }
        )
    }

    /// The keyboard would cover half the form in CI screenshots, so debug launches that show the form skip it.
    private var autofocus: Bool {
        #if DEBUG
        return LaunchOptions.addEvent == nil
        #else
        return true
        #endif
    }
}
