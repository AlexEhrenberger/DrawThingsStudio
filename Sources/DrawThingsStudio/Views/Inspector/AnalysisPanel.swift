import SwiftUI

/// Bilder mit Gemma (Vision) analysieren und daraus Prompts bauen.
struct AnalysisPanel: View {
    @Environment(Studio.self) private var studio
    @State private var question = ""
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sourceCard
                actions
                questionField
                if !studio.analysisResults.isEmpty {
                    HStack {
                        Text("Ergebnisse")
                            .font(.headline)
                        Spacer()
                        Button("Leeren") { studio.analysisResults.removeAll() }
                            .buttonStyle(.borderless)
                            .font(.callout)
                    }
                    .padding(.top, 4)
                    ForEach(studio.analysisResults) { result in
                        AnalysisResultCard(result: result)
                    }
                }
            }
            .padding(14)
            .animation(.smooth, value: studio.analysisResults.map(\.id))
        }
    }

    private var sourceCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let image = studio.analysisSource == nil ? studio.current?.thumbnail : studio.analysisThumbnail {
                    CGImageView(image: image, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 72, height: 72)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.analysisSource == nil ? "Bild auf dem Canvas" : "Eigenes Bild")
                    .font(.headline)
                Text(studio.analysisImage == nil ? "Ziehe ein Bild hierher oder wähle eines aus." : "Gemma sieht dieses Bild.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Anderes Bild …") {
                        if let image = studio.chooseImage(message: "Bild zum Analysieren wählen") { studio.analysisSource = image }
                    }
                    if studio.analysisSource != nil {
                        Button("Canvas") { studio.analysisSource = nil }
                    }
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .card()
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            Task {
                if let image = await DropLoader.loadImage(from: providers) { studio.analysisSource = image }
            }
            return true
        }
    }

    private var actions: some View {
        let available = studio.analysisImage != nil
        return VStack(spacing: 8) {
            action(.reversePrompt, "Prompt aus Bild", "Qwen-Prompt, der das Bild nachbaut")
            action(.recognize, "Bausteine erkennen", "Wählt passende Chips im Prompt Builder")
            HStack(spacing: 8) {
                action(.subject, "Subjekt", nil)
                action(.style, "Stil & Licht", nil)
            }
            action(.text, "Text erkennen", "Apple Vision – danach direkt ersetzen")
        }
        .disabled(!available)
    }

    private func action(_ kind: AnalysisKind, _ title: String, _ detail: String?) -> some View {
        Button {
            studio.analyze(kind)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.title3)
                    .foregroundStyle(GemmaStyle.gradient)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, detail == nil ? 9 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var questionField: some View {
        HStack(spacing: 6) {
            TextField("Frage zum Bild …", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit(ask)
            Button(action: ask) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(question.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(GemmaStyle.gradient))
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || studio.analysisImage == nil)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, studio.analysisImage != nil else { return }
        studio.analyze(.question, question: text)
        question = ""
    }
}

private struct AnalysisResultCard: View {
    @Environment(Studio.self) private var studio
    let result: AnalysisResult
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let thumbnail = result.thumbnail {
                    CGImageView(image: thumbnail, contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Label(result.kind.title, systemImage: result.kind.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if result.isRunning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    studio.removeResult(result)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if let question = result.question {
                Text(question)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
            if !result.text.isEmpty {
                Text(result.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.recognized.isEmpty {
                recognizedList
            }
            if !result.lines.isEmpty {
                textLines
            }
            if let error = result.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !result.isRunning && result.error == nil {
                footer
            }
        }
        .card()
    }

    private var recognizedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(PromptTemplates.recognizableGroups.filter { result.recognized[$0] != nil }, id: \.self) { key in
                if let group = Catalog.shared.group(key), let ids = result.recognized[key] {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: group.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(group.name)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(group.options.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var textLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("„\(line)“")
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Ersetzen …") { studio.prepareTextReplacement(line) }
                        .controlSize(.small)
                        .help("Öffnet „Text im Bild › Ersetzen“ mit diesem Text – dort nur noch den neuen Text eintragen.")
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if result.kind == .text {
                EmptyView()
            } else if result.kind == .recognize {
                if !result.recognized.isEmpty {
                    Button("Bausteine übernehmen", systemImage: "checkmark.circle") { studio.applyRecognized(result) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                if result.kind.producesPrompt {
                    Button("Als Prompt") { studio.usePromptText(result.text, append: false) }
                        .buttonStyle(.borderedProminent)
                    Button("Anhängen") { studio.usePromptText(result.text, append: true) }
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Kopieren")
            }
        }
        .controlSize(.small)
    }
}
