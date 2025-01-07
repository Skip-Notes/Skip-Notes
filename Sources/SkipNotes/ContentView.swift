import SwiftUI
import Foundation
import OSLog
import SkipNotesModel

fileprivate let logger: Logger = Logger(subsystem: "skip.app.notes", category: "SkipNotes")

public struct ContentView: View {
    @State var viewModel = ViewModel.shared
    @State var appearance = ""
    @State var showSettings = false

    public init() {
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: item) {
                        Label {
                            Text(item.itemTitle)
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
                    .navigationTitle(item.itemTitle)
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

    var body: some View {
        Form {
            TextField("Title", text: $item.title)
                .textFieldStyle(.roundedBorder)
            Toggle("Favorite", isOn: $item.favorite)
            DatePicker("Date", selection: $item.date)
            Text("Notes").font(.title3)
            TextEditor(text: $item.notes)
                .border(Color.secondary, width: 1.0)
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
