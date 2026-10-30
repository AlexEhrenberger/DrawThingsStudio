import SwiftUI

// MARK: - Zuschneiden & Ausrichten

struct CropPanel: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if let current = studio.current {
            form(current)
        } else {
            NoImageView(symbol: "crop.rotate", text: "Generiere oder öffne ein Bild – dann kannst du es hier zuschneiden, begradigen und drehen.")
        }
    }

    private func form(_ current: ImageVersion) -> some View {
        @Bindable var studio = studio
        let pixelRatio = Double(current.image.width) / Double(current.image.height)
        return Form {
            Section {
                FlowLayout(spacing: 5, lineSpacing: 5) {
                    Chip(title: "Frei", isOn: studio.crop.ratioID == "free") { studio.setCropRatio("free", ratio: nil) }
                    Chip(title: "Original", isOn: studio.crop.ratioID == "original") { studio.setCropRatio("original", ratio: pixelRatio) }
                    ForEach(AspectRatio.all) { ratio in
                        Chip(title: ratio.label, isOn: studio.crop.ratioID == ratio.id) { studio.setCropRatio(ratio.id, ratio: ratio.value) }
                            .help(ratio.name)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Format")
            } footer: {
                Text("Ziehe Ecken, Kanten oder die Mitte des Rahmens direkt auf dem Bild.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ausrichten") {
                AdjustSlider(title: "Begradigen", value: $studio.crop.angle, spec: SliderSpecs.straighten)
                HStack {
                    Button {
                        studio.autoStraighten()
                    } label: {
                        Label("Horizont automatisch", systemImage: "level")
                    }
                    .disabled(studio.visionTask != nil)
                    Spacer()
                    if studio.visionTask == .horizon { VisionBusyLabel(text: "Vision sucht …") }
                }
            }

            Section {
                HStack {
                    Button {
                        studio.smartCrop()
                    } label: {
                        Label("Auf das Motiv zuschneiden", systemImage: "viewfinder")
                    }
                    .disabled(studio.visionTask != nil)
                    Spacer()
                    if studio.visionTask == .saliency { VisionBusyLabel(text: "Vision sucht …") }
                }
            } header: {
                Text("Intelligent")
            } footer: {
                Text("Apple Vision findet den Bereich, auf den das Auge zuerst fällt, und legt den Rahmen im gewählten Format darum.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Drehen & Spiegeln") {
                HStack(spacing: 6) {
                    ToolButton(symbol: "rotate.left", help: "Nach links drehen") { studio.transform(.rotateLeft) }
                    ToolButton(symbol: "rotate.right", help: "Nach rechts drehen") { studio.transform(.rotateRight) }
                    ToolButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Horizontal spiegeln") { studio.transform(.flipHorizontal) }
                    ToolButton(symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", help: "Vertikal spiegeln") { studio.transform(.flipVertical) }
                }
            }

            Section("Größe") {
                LabeledContent("Aktuell") {
                    Text("\(Format.size(current.size)) px").monospacedDigit()
                }
                Button {
                    studio.upscale()
                } label: {
                    Label("2× hochskalieren", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Lanczos-Skalierung mit leichter Nachschärfung (Core Image).")
            }

            Section {
                HStack {
                    Button("Zurücksetzen") { studio.resetCrop() }
                        .disabled(studio.crop.isIdentity)
                    Spacer()
                    Button("Zuschneiden") { studio.applyCrop() }
                        .buttonStyle(.borderedProminent)
                        .disabled(studio.crop.isIdentity)
                }
            } footer: {
                Text("Das Ergebnis wird eine neue Version – das Original bleibt im Verlauf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .panelFormBackground()
    }
}

// MARK: - Auswahl

struct SelectionPanel: View {
    @Environment(Studio.self) private var studio
    @State private var blurAmount = 0.5
    @State private var backgroundColor = Color.white

    var body: some View {
        if studio.current != nil {
            form
        } else {
            NoImageView(symbol: "lasso", text: "Generiere oder öffne ein Bild – dann kannst du hier Motive auswählen und gezielt bearbeiten.")
        }
    }

    private var form: some View {
        @Bindable var studio = studio
        return Form {
            Section {
                HStack(spacing: 8) {
                    Button {
                        studio.selectSubject(peopleOnly: false)
                    } label: {
                        Label("Motiv", systemImage: "person.and.background.dotted")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        studio.selectSubject(peopleOnly: true)
                    } label: {
                        Label("Personen", systemImage: "person.2")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(studio.visionTask != nil)
                if studio.visionTask == .subject || studio.visionTask == .people {
                    VisionBusyLabel(text: "Vision stellt frei …")
                }
            } header: {
                Text("Automatisch auswählen")
            } footer: {
                Text("Apple Vision erkennt das Hauptmotiv wie „Motiv anheben“ in Fotos – lokal, ohne Internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pinsel") {
                Picker("Werkzeug", selection: $studio.selectionTool) {
                    ForEach(SelectionTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                AdjustSlider(title: "Größe", value: $studio.brushDiameter, spec: SliderSpecs.brush)
            }

            Section {
                HStack(spacing: 8) {
                    Button("Umkehren", systemImage: "arrow.left.arrow.right.square") { studio.invertSelection() }
                    Button("Aufheben", systemImage: "xmark.square") { studio.clearSelection() }
                }
                .disabled(!studio.hasSelection)
                AdjustSlider(title: "Weiche Kante", value: $studio.selectionFeather, spec: SliderSpecs.feather)
                Toggle("Auswahl auf dem Bild zeigen", isOn: $studio.showSelectionOverlay)
            } header: {
                Text("Auswahl")
            }

            Section {
                Toggle("Qwen-Ergebnis nur in der Auswahl übernehmen", isOn: $studio.applyEditToSelection)
                    .disabled(!studio.hasSelection)
                if studio.mode != .edit {
                    Button("Zu „Bearbeiten“ wechseln") { studio.mode = .edit }
                        .controlSize(.small)
                }
            } header: {
                Text("KI-Bearbeitung")
            } footer: {
                Text("Draw Things nimmt über HTTP keine Masken an. Qwen bearbeitet deshalb das ganze Bild, und die App übernimmt danach nur den ausgewählten Bereich – der Rest bleibt pixelgenau erhalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    studio.applyBackground(.transparent)
                } label: {
                    Label("Freistellen (transparent)", systemImage: "square.dashed")
                }
                HStack {
                    Button {
                        studio.applyBackground(.blur(blurAmount))
                    } label: {
                        Label("Weichzeichnen", systemImage: "camera.aperture")
                    }
                    Slider(value: $blurAmount, in: 0.1...1)
                        .controlSize(.small)
                        .labelsHidden()
                }
                Button {
                    studio.applyBackground(.monochrome)
                } label: {
                    Label("Schwarzweiß (Color Key)", systemImage: "circle.lefthalf.filled")
                }
                HStack {
                    Button {
                        studio.applyBackground(.color(NSColor(backgroundColor).cgColor))
                    } label: {
                        Label("Einfärben", systemImage: "paintbrush")
                    }
                    Spacer()
                    ColorPicker("Farbe", selection: $backgroundColor, supportsOpacity: false)
                        .labelsHidden()
                }
            } header: {
                Text("Hintergrund außerhalb der Auswahl")
            } footer: {
                Text("Jede Aktion legt eine neue Version an. Freigestellte Bilder behalten beim Export als PNG ihre Transparenz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!studio.hasSelection)
        }
        .formStyle(.grouped)
        .panelFormBackground()
    }
}
