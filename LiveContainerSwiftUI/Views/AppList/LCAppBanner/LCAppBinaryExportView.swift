//
//  LCAppBinaryExportView.swift
//  LiveContainerSwiftUI
//

import SwiftUI

struct LCAppBinaryExportView: View {
    let items: [AppBinaryExportItem]
    let onCancel: () -> Void
    let onExport: ([AppBinaryExportItem]) -> Void
    let onCopyToTweaks: ([AppBinaryExportItem]) -> Void

    @State private var selectedItemIDs: Set<String>

    init(
        items: [AppBinaryExportItem],
        onCancel: @escaping () -> Void,
        onExport: @escaping ([AppBinaryExportItem]) -> Void,
        onCopyToTweaks: @escaping ([AppBinaryExportItem]) -> Void
    ) {
        self.items = items
        self.onCancel = onCancel
        self.onExport = onExport
        self.onCopyToTweaks = onCopyToTweaks
        _selectedItemIDs = State(initialValue: Set(items.map(\.id)))
    }

    private var selectedItems: [AppBinaryExportItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var body: some View {
        NavigationView {
            List {
                if items.isEmpty {
                    Text("No .dylib or .framework was found in this app bundle.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        Button {
                            if selectedItemIDs.contains(item.id) {
                                selectedItemIDs.remove(item.id)
                            } else {
                                selectedItemIDs.insert(item.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedItemIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.relativePath)
                                        .font(.system(.body, design: .monospaced))
                                    Text(item.kind.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Export Dylibs & Frameworks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !items.isEmpty {
                        Button(selectedItemIDs.count == items.count ? "Unselect All" : "Select All") {
                            if selectedItemIDs.count == items.count {
                                selectedItemIDs.removeAll()
                            } else {
                                selectedItemIDs = Set(items.map(\.id))
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        onExport(selectedItems)
                    }
                    .disabled(selectedItems.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Copy to Tweaks") {
                        onCopyToTweaks(selectedItems)
                    }
                    .disabled(selectedItems.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
