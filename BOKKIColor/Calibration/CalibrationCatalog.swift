import Foundation

/// CALIB1102: what BOKKI CAM can ask of the chart library besides a fixed chart id.

/// One row of the `catalog` answer: enough for the CAM to list a chart and pick it.
struct CalibrationChartInfo: Codable, Equatable {
    var id: String
    var title: String
    /// Chart category id: reference, combo, gray, wb, skin, hue, video, custom.
    var category: String
    var subtitle: String?
    var rows: Int
    var columns: Int
    var count: Int
    var source: String?
}

/// A patch the CAM defines itself in a `patches` target: Display P3 code values, or CIE L*a*b* (D50).
struct CalibrationCustomPatch: Codable, Equatable {
    var name: String?
    var p3: [Double]?
    var lab: [Double]?
}

enum CalibrationCatalog {
    /// Most patches one `patches` target may carry.
    static let maxCustomPatches = 1024

    struct Entry {
        var info: CalibrationChartInfo
        var chart: PatchChart
    }

    /// Every chart the CAM can show as a grid: built-in references, generated grays, skin tones, hue grids and so on,
    /// plus the user's custom charts. Free-layout cards and pattern charts (ramps, slate) are not grids and are left out.
    static func entries(custom: [PatchChart]) -> [Entry] {
        var seen = Set<String>()
        var out: [Entry] = []
        for category in ChartCatalog.categories(custom: custom) {
            for item in category.items {
                guard case .patches(let chart) = item.kind, chart.layoutRects == nil,
                      chart.patches.count == chart.rows * chart.columns, seen.insert(chart.id).inserted else { continue }
                let info = CalibrationChartInfo(id: chart.id, title: chart.title, category: category.id,
                                                subtitle: chart.subtitle.isEmpty ? nil : chart.subtitle,
                                                rows: chart.rows, columns: chart.columns, count: chart.patches.count,
                                                source: chart.source.isEmpty ? nil : chart.source)
                out.append(Entry(info: info, chart: chart))
            }
        }
        return out
    }

    /// Checks a `patches` target and builds the grid to draw. The error text goes back to the CAM.
    static func chart(rows: Int, columns: Int, patches: [CalibrationCustomPatch]) -> Result<PatchChart, ValidationError> {
        guard rows >= 1, columns >= 1, rows * columns == patches.count else {
            return .failure(ValidationError(message: "patches needs rows * columns patches"))
        }
        guard patches.count <= maxCustomPatches else {
            return .failure(ValidationError(message: "at most \(maxCustomPatches) patches"))
        }
        var built: [Patch] = []
        for (i, p) in patches.enumerated() {
            let name = p.name ?? "\(i + 1)"
            if let p3 = p.p3 {
                guard p3.count == 3, p3.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                    return .failure(ValidationError(message: "patch \(i): p3 needs three values in 0...1"))
                }
                built.append(Patch(name: name, spec: .encoded(Vec3(p3[0], p3[1], p3[2]), space: .displayP3)))
            } else if let lab = p.lab {
                guard lab.count == 3, lab.allSatisfy(\.isFinite), (0...100).contains(lab[0]), lab[1...].allSatisfy({ abs($0) <= 200 }) else {
                    return .failure(ValidationError(message: "patch \(i): lab needs L* 0...100 and a*, b* within 200"))
                }
                built.append(Patch(name: name, spec: .lab(lab[0], lab[1], lab[2])))
            } else {
                return .failure(ValidationError(message: "patch \(i): needs p3 or lab"))
            }
        }
        return .success(PatchChart(id: "custom", title: "", rows: rows, columns: columns, patches: built))
    }

    struct ValidationError: Error { var message: String }
}
