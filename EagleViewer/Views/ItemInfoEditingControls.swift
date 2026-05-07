//
//  ItemInfoEditingControls.swift
//  EagleViewer
//
//  Created on 2026/05/07.
//

import SwiftUI

struct ItemInfoRatingEditor: View {
    let rating: Int
    let setRating: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { value in
                Button {
                    setRating(value == rating ? 0 : value)
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(value <= rating ? Color.yellow : Color.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set rating \(value)")
                .accessibilityValue("\(rating) of 5")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ItemInfoTagEditor: View {
    let tags: [String]
    let addTag: (String) -> Void
    let removeTag: (String) -> Void

    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)

            FlowLayout(alignment: .leading) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(verbatim: tag)
                            .lineLimit(1)

                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                    .modifier(ItemInfoTag())
                }
            }

            HStack(spacing: 8) {
                TextField("Add tag", text: $newTag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addPendingTag)

                Button(action: addPendingTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add tag")
            }
        }
    }

    private func addPendingTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else {
            return
        }

        addTag(tag)
        newTag = ""
    }
}

struct ItemInfoAnnotationEditor: View {
    @Binding var annotation: String
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)

            TextEditor(text: $annotation)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(AppTheme.Colors.subtleFill)
                )

            Button(action: save) {
                Label("Save Notes", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
