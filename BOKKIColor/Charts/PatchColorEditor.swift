import SwiftUI

/// Colour models the editor works in. Each maps a patch's `ColorSpec` to three channel values and back.
private enum EditModel: String, CaseIterable, Identifiable {
    case lab = "Lab", lch = "LCh", rgb = "RGB", hsv = "HSV"
    var id: String { rawValue }
}

private enum RGBDepth: Int, CaseIterable, Identifiable {
    case bit8 = 8, bit10 = 10, bit16 = 16
    var id: Int { rawValue }
    var maxCode: Double { Double((1 << rawValue) - 1) }
}

/// Step size multiplier for the − / + buttons and slider snapping.
private enum Precision: Double, CaseIterable, Identifiable {
    case coarse = 10, normal = 1, fine = 0.1, ultra = 0.01
    var id: Double { rawValue }
    var title: String {
        switch self {
        case .coarse: tr("거칠게")
        case .normal: tr("보통")
        case .fine: tr("정밀")
        case .ultra: tr("초정밀")
        }
    }
}

private struct Channel {
    let name: String
    let range: ClosedRange<Double>
    /// Step at "보통" precision, in displayed units.
    let step: Double
    /// Displayed value = model value × scale (RGB code values, HSV percent).
    let scale: Double
    let decimals: Int
}

/// Professional-style editor for one patch: before/after swatch with ΔE, per-channel gradient tracks,
/// numeric entry with selectable step, hex entry, and undo / redo.
struct PatchColorEditor: View {
    @Binding var patch: Patch
    let original: Patch?
    let space: OutputSpace

    @State private var model: EditModel = .lab
    @State private var depth: RGBDepth = .bit8
    @State private var precision: Precision = .normal
    @State private var values = Vec3(0, 0, 0)
    @State private var history: [ColorSpec] = []
    @State private var cursor = 0
    @State private var hex = ""
    @FocusState private var hexFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                swatches
                readout
                controls
                channelCard
                if model == .rgb { hexCard }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(tr("색상 편집"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(cursor == 0).accessibilityLabel(tr("실행 취소"))
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(cursor >= history.count - 1).accessibilityLabel(tr("다시 실행"))
            }
        }
        .onAppear {
            history = [patch.spec]
            cursor = 0
            sync()
        }
        .onChange(of: model) { sync() }
        .onChange(of: space) { sync() }
    }

    // MARK: Header

    private var swatches: some View {
        HStack(spacing: 0) {
            swatch(original?.spec ?? patch.spec, title: tr("기준"))
            swatch(patch.spec, title: tr("현재"))
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.secondary.opacity(0.35)))
    }

    private func swatch(_ spec: ColorSpec, title: String) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(spec.color(in: space))
            Text(title).font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white).padding(8)
        }
    }

    private var readout: some View {
        let now = patch.spec.labD50
        let base = (original?.spec ?? patch.spec).labD50
        let dE = ColorMath.deltaE2000(base, now)
        return VStack(spacing: 8) {
            HStack {
                Text("ΔE2000").font(.caption.bold()).foregroundStyle(.secondary)
                Text(String(format: "%.2f", dE)).font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(dE < 1 ? Color.green : dE < 3 ? Color.yellow : Color.orange)
                Spacer()
                if patch.spec.outOfGamut(in: space) {
                    Label(tr("개멋 밖, 클립됨"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold()).foregroundStyle(.orange)
                }
            }
            HStack {
                delta("ΔL*", now.x - base.x)
                delta("Δa*", now.y - base.y)
                delta("Δb*", now.z - base.z)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func delta(_ name: String, _ v: Double) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.caption.bold()).foregroundStyle(.secondary)
            Text(String(format: "%+.2f", v)).font(.system(.callout, design: .monospaced))
            Spacer(minLength: 0)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            Picker(tr("색 모델"), selection: $model) { ForEach(EditModel.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            if model == .rgb {
                Picker(tr("비트 심도"), selection: $depth) { ForEach(RGBDepth.allCases) { Text("\($0.rawValue) bit").tag($0) } }
                    .pickerStyle(.segmented)
            }
            Picker(tr("조정 간격"), selection: $precision) { ForEach(Precision.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented)
        }
    }

    private var channels: [Channel] {
        switch model {
        case .lab:
            [Channel(name: "L*", range: 0...100, step: 0.1, scale: 1, decimals: 2),
             Channel(name: "a*", range: -128...128, step: 0.1, scale: 1, decimals: 2),
             Channel(name: "b*", range: -128...128, step: 0.1, scale: 1, decimals: 2)]
        case .lch:
            [Channel(name: "L*", range: 0...100, step: 0.1, scale: 1, decimals: 2),
             Channel(name: "C*", range: 0...181, step: 0.1, scale: 1, decimals: 2),
             Channel(name: "h°", range: 0...360, step: 0.5, scale: 1, decimals: 1)]
        case .rgb:
            ["R", "G", "B"].map { Channel(name: $0, range: 0...depth.maxCode, step: 1, scale: depth.maxCode, decimals: 0) }
        case .hsv:
            [Channel(name: "H°", range: 0...360, step: 0.5, scale: 1, decimals: 1),
             Channel(name: "S%", range: 0...100, step: 0.5, scale: 100, decimals: 1),
             Channel(name: "V%", range: 0...100, step: 0.5, scale: 100, decimals: 1)]
        }
    }

    private var channelCard: some View {
        VStack(spacing: 14) {
            ForEach(Array(channels.enumerated()), id: \.offset) { i, ch in
                ChannelRow(channel: ch, displayValue: values[i] * ch.scale, step: ch.step * precision.rawValue,
                           stops: stops(for: i, channel: ch)) { shown in
                    set(i, shown / ch.scale)
                } onCommit: {
                    commit()
                } onReset: {
                    resetChannel(i)
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var hexCard: some View {
        HStack {
            Text("HEX").font(.caption.bold()).foregroundStyle(.secondary)
            Text("#").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            TextField("RRGGBB", text: $hex)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .focused($hexFocused)
                .onSubmit(applyHex)
                .onChange(of: hexFocused) { if !hexFocused { applyHex() } }
            Spacer()
            Text(space.title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Model <-> spec

    private func read(_ spec: ColorSpec) -> Vec3 {
        switch model {
        case .lab: return spec.labD50
        case .lch: return ColorMath.labToLCh(spec.labD50)
        case .rgb: return spec.encoded(in: space)
        case .hsv: return ColorMath.rgbToHSV(spec.encoded(in: space))
        }
    }

    private func make(_ v: Vec3) -> ColorSpec {
        switch model {
        case .lab: return .lab(v.x, v.y, v.z)
        case .lch:
            let l = ColorMath.lchToLab(v)
            return .lab(l.x, l.y, l.z)
        case .rgb: return .encoded(clamp01(v), space: space)
        case .hsv: return .encoded(clamp01(ColorMath.hsvToRGB(v)), space: space)
        }
    }

    private func clamp01(_ v: Vec3) -> Vec3 { v.clamped(lowerBound: Vec3(repeating: 0), upperBound: Vec3(repeating: 1)) }

    /// Colours along channel `i` with the other two held, so the track previews what dragging does.
    private func stops(for i: Int, channel ch: Channel) -> [Color] {
        let n = 24
        return (0...n).map { k in
            var v = values
            let t = ch.range.lowerBound + (ch.range.upperBound - ch.range.lowerBound) * Double(k) / Double(n)
            v[i] = t / ch.scale
            return make(v).color(in: space)
        }
    }

    private func sync() {
        values = read(patch.spec)
        hex = Self.hexString(patch.spec, space)
    }

    private func set(_ i: Int, _ v: Double) {
        values[i] = v
        patch.spec = make(values)
        patch.tuned = true
        if !hexFocused { hex = Self.hexString(patch.spec, space) }
    }

    private func resetChannel(_ i: Int) {
        guard let original else { return }
        set(i, read(original.spec)[i])
        commit()
    }

    private func applyHex() {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard digits.count == 6, let code = UInt32(digits, radix: 16) else { hex = Self.hexString(patch.spec, space); return }
        let v = Vec3(Double(code >> 16 & 0xFF), Double(code >> 8 & 0xFF), Double(code & 0xFF)) / 255
        patch.spec = .encoded(v, space: space)
        patch.tuned = true
        sync()
        commit()
    }

    private static func hexString(_ spec: ColorSpec, _ space: OutputSpace) -> String {
        let c = spec.code8(in: space)
        return String(format: "%02X%02X%02X", c.0, c.1, c.2)
    }

    // MARK: History

    private func commit() {
        guard history[cursor] != patch.spec else { return }
        history = Array(history[...cursor]) + [patch.spec]
        cursor = history.count - 1
    }

    private func undo() { jump(cursor - 1) }
    private func redo() { jump(cursor + 1) }

    private func jump(_ index: Int) {
        guard history.indices.contains(index) else { return }
        cursor = index
        patch.spec = history[index]
        // Back at the first state means untouched, unless the chart was already tuned before this session.
        if index == 0, original?.spec == history[0] { patch.tuned = nil }
        sync()
    }
}

/// One channel: name, gradient track, numeric field and −/+ buttons. Double-tap the name to reset it.
private struct ChannelRow: View {
    let channel: Channel
    let displayValue: Double
    let step: Double
    let stops: [Color]
    let onChange: (Double) -> Void
    let onCommit: () -> Void
    let onReset: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var format: String { "%.\(channel.decimals)f" }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(channel.name).font(.system(.callout, design: .monospaced).bold())
                    .frame(width: 34, alignment: .leading)
                    .onTapGesture(count: 2, perform: onReset)
                GradientSlider(value: displayValue, range: channel.range, step: step, stops: stops,
                               onChange: onChange, onEnd: onCommit)
                TextField("", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(.callout, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit(commitText)
                    .frame(width: 70)
                    .padding(.vertical, 5).padding(.horizontal, 6)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 2) {
                    nudge("minus", -1)
                    nudge("plus", 1)
                }
            }
        }
        .onAppear { text = String(format: format, displayValue) }
        .onChange(of: displayValue) { if !focused { text = String(format: format, displayValue) } }
        .onChange(of: channel.decimals) { text = String(format: format, displayValue) }
        .onChange(of: focused) { if !focused { commitText() } }
    }

    private func nudge(_ symbol: String, _ direction: Double) -> some View {
        Button {
            onChange(clamp(((displayValue / step).rounded() + direction) * step))
            onCommit()
        } label: {
            Image(systemName: symbol).font(.caption.bold()).frame(width: 28, height: 28)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? tr("감소") : tr("증가"))
    }

    private func clamp(_ v: Double) -> Double { min(channel.range.upperBound, max(channel.range.lowerBound, v)) }

    private func commitText() {
        if let v = Double(text.replacingOccurrences(of: ",", with: ".")) {
            onChange(clamp(v))
            onCommit()
        }
        text = String(format: format, displayValue)
    }
}

/// Slider whose track is the gradient of colours the channel sweeps through.
private struct GradientSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let stops: [Color]
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let x = span > 0 ? (value - range.lowerBound) / span * w : 0
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 14)
                    .overlay(Capsule().stroke(.secondary.opacity(0.4)))
                Circle().fill(.white).frame(width: 24, height: 24)
                    .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                    .shadow(radius: 1.5)
                    .offset(x: min(max(x, 0), w) - 12)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let t = min(max(g.location.x / max(w, 1), 0), 1)
                    let raw = range.lowerBound + t * span
                    onChange(min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step)))
                }
                .onEnded { _ in onEnd() })
        }
        .frame(height: 28)
        .accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? step : -step
            onChange(min(range.upperBound, max(range.lowerBound, value + delta)))
            onEnd()
        }
    }
}
