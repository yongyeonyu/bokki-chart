import SwiftUI

/// Values of one patch in both output spaces at 24 / 16 / 8 (and 10) bit.
struct PatchDetailView: View {
    @Binding var patch: Patch
    /// Default value of this patch; nil when the patch cannot be tuned (slate strip, sequence).
    var original: Patch?
    var editable = false
    @AppStorage(SettingsKey.outputSpace) private var current: OutputSpace = .displayP3
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 8).fill(patch.spec.color(in: current))
                            .frame(width: 72, height: 72)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(patch.name).font(.headline)
                                if patch.tuned == true { Text(tr("튜닝됨")).font(.caption2.bold()).padding(.horizontal, 6).background(.orange, in: Capsule()) }
                            }
                            if let ref = original?.reference ?? patch.reference {
                                Text((patch.tuned == true ? tr("기본값 ") : "") + ref).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            let lab = patch.spec.lab(in: current)
                            Text(String(format: tr("표시 Lab(D50) %.1f / %.1f / %.1f"), lab.x, lab.y, lab.z))
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
                if editable {
                    Section {
                        NavigationLink {
                            PatchColorEditor(patch: $patch, original: original, space: current)
                        } label: {
                            Label(tr("색상 편집"), systemImage: "slider.horizontal.3")
                        }
                        if let original, patch.tuned == true {
                            Button(tr("이 패치 기본값으로"), role: .destructive) { patch = original }
                        }
                    } footer: {
                        Text(tr("Lab · LCh · RGB · HSV로 세밀하게 조정합니다. 체커 화면에 바로 반영되며, 상단 '저장'으로 커스텀 체커로 보관하세요."))
                    }
                }
                ForEach([current] + OutputSpace.allCases.filter { $0 != current }) { space in
                    let info = ColorInfo(patch.spec, space: space)
                    Section {
                        ForEach(info.lines, id: \.0) { line in
                            LabeledContent(line.0) {
                                Text(line.1).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    } header: {
                        HStack {
                            Text(space.title + (space == current ? tr(" (현재 출력)") : ""))
                            if info.outOfGamut { Text(tr("· 개멋 밖, 클립됨")).foregroundStyle(.orange) }
                        }
                    }
                }
            }
            .navigationTitle(tr("패치 색상 정보"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(copied ? tr("복사됨") : tr("복사")) {
                    UIPasteboard.general.string = "\(patch.name)\n" + (patch.reference.map { "\($0)\n" } ?? "")
                        + OutputSpace.allCases.map { ColorInfo(patch.spec, space: $0).copyText }.joined(separator: "\n\n")
                    copied = true
                }
            }
        }
    }
}
