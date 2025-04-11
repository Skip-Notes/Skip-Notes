import Foundation
import SkipFuseUI
import SkipKit
import SkipNotesModel

struct ContentView: View {
    @State var viewModel = ViewModel.shared
    @State var appearance = ""
    @State var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: item) {
                        Label {
                            item.itemTitleText
                        } icon: {
                            if item.favorite {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    viewModel.remove(atOffsets: Array(offsets))
                }
                .onMove { fromOffsets, toOffset in
                    viewModel.move(fromOffsets: Array(fromOffsets), toOffset: toOffset)
                }
            }
            .searchable(text: $viewModel.filter)
            .navigationTitle(Text("\(viewModel.items.count) Notes"))
            .navigationDestination(for: Item.self) { item in
                ItemView(item: item, viewModel: $viewModel)
                    .navigationTitle(item.itemTitleText)
            }
            .toolbar {
                #if os(macOS)
                let placement: ToolbarItemPlacement = .automatic
                #else
                let placement: ToolbarItemPlacement = .bottomBar // unavailable on macOS
                #endif
                ToolbarItemGroup(placement: placement) {
                    Button {
                        withAnimation {
                            let _ = viewModel.addItem()
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Spacer()
                    Button {
                        self.showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showSettings, content: {
                SettingsView(appearance: $appearance, viewModel: $viewModel)
            })
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}


struct SettingsView : View {
    @Binding var appearance: String
    @Binding var viewModel: ViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle(isOn: $viewModel.encrypted) {
                    HStack {
                        Text("Encrypt")
                        Spacer()
                        if viewModel.crypting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                    }
                }
                .disabled(viewModel.crypting)
                Toggle(isOn: $viewModel.useLocation) {
                    HStack {
                        Text("Use Location")
                    }
                }
                Text(viewModel.locationDescription)

                HStack {
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("Version \(version) (\(buildNumber))")
                            .foregroundStyle(.gray)
                    }
                    Text("Powered by [Skip](https://skip.tools)")
                }
                .foregroundStyle(.gray)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ItemView : View {
    @State var item: Item
    @Binding var viewModel: ViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState var focusField: FocusField?

    enum FocusField { case title, notes }

    var body: some View {
        Form {
            TextField("Title", text: $item.title)
                .focused($focusField, equals: .title)
                .textFieldStyle(.roundedBorder)
            Toggle("Favorite", isOn: $item.favorite)
            DatePicker("Date", selection: $item.date)
            Text("Notes")
                .font(.title3)
            TextEditor(text: $item.notes)
                .focused($focusField, equals: .notes)
                .border(Color.secondary, width: 1.0)
        }
        .onAppear {
            if item.title.isEmpty && item.notes.isEmpty {
                focusField = .title
            } else if item.notes.isEmpty {
                focusField = .notes
            }
        }
        .navigationBarBackButtonHidden() // we use a "Cancel" button in place of the back button
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save(item: item)
                    dismiss()
                }
                .disabled(!viewModel.isUpdated(item))
            }
        }
    }
}

extension Item {
    /// Returns the title of the note, or else the localized default title "New Note"
    var itemTitleText: Text {
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = self.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if !title.isEmpty && !notes.isEmpty {
            return Text(verbatim: title + ": " + notes)
        } else if !title.isEmpty {
            return Text(verbatim: title)
        } else if !notes.isEmpty {
            return Text(verbatim: notes)
        } else {
            return Text("New Note")
        }
    }
}
