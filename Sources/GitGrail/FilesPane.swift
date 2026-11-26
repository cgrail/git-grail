import GrailCore
import SwiftUI

/// The changed files with a checkbox to leave a file out of the commit, and the commit box.
struct FilesPane: View {
    @Environment(AppModel.self) private var model
    let wt: String
    @ViewState private var message = ""

    var body: some View {
        @Bindable var model = model
        let skip = model.excluded[wt] ?? []
        let included = model.files.filter { !skip.contains($0.path) }.count
        VStack(spacing: 0) {
            List(selection: $model.selectedFile) {
                ForEach(model.files) { f in
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding { !skip.contains(f.path) } set: { _ in model.toggleExcluded(wt, f.path) })
                            .labelsHidden()
                            .help("Include this file in the commit")
                        Text(f.code.trimmingCharacters(in: .whitespaces))
                            .font(.caption.monospaced().bold()).foregroundStyle(color(f.code)).frame(width: 20)
                        Text(f.path).lineLimit(1).truncationMode(.head)
                            .foregroundStyle(skip.contains(f.path) ? .secondary : .primary)
                        Spacer()
                        Button { Task { await model.resetFile(wt, f) } } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.borderless)
                            .help("Reset this file. Redo brings it back.")
                    }
                    .tag(f.path)
                }
            }
            .overlay { if model.files.isEmpty { Text("No changes").foregroundStyle(.secondary) } }
            .onChange(of: model.selectedFile) { Task { await model.loadDiff(wt) } }
            Divider()
            VStack(alignment: .trailing, spacing: 6) {
                TextField("Commit message", text: $message, axis: .vertical).lineLimit(2...5)
                Button("Commit \(included) of \(model.files.count) files") {
                    Task { await model.commit(wt, message: message); message = "" }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || included == 0 || model.busy)
            }
            .padding(8)
        }
    }

    private func color(_ code: String) -> Color {
        if code == "??" || code.contains("A") { return .green }
        if code.contains("D") { return .red }
        if code.contains("U") { return .orange }
        return .blue
    }
}

/// A fast diff view: it draws only the visible lines.
struct DiffView: View {
    let text: String
    static let maxLines = 20_000

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(Self.maxLines)
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : String(line))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(color(line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line))
                }
            }
            .textSelection(.enabled)
            .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay { if text.isEmpty { Text("Select a file to see its diff").foregroundStyle(.secondary) } }
    }

    private func color(_ line: Substring) -> Color {
        if line.hasPrefix("@@") { return .purple }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .primary
    }

    private func background(_ line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red.opacity(0.08) }
        return .clear
    }
}
