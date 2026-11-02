import Foundation

/// Conversions and difference metrics the colour editor needs; dependency-free like `ColorMath`.
extension ColorMath {
    /// CIE L*a*b* -> L*, C*ab, h° (0..<360).
    static func labToLCh(_ lab: Vec3) -> Vec3 {
        let h = atan2(lab.z, lab.y) * 180 / .pi
        return Vec3(lab.x, hypot(lab.y, lab.z), h < 0 ? h + 360 : h)
    }

    static func lchToLab(_ lch: Vec3) -> Vec3 {
        let r = lch.z * .pi / 180
        return Vec3(lch.x, lch.y * cos(r), lch.y * sin(r))
    }

    /// Gamma-encoded RGB (0...1) -> hue° (0..<360), saturation, value.
    static func rgbToHSV(_ rgb: Vec3) -> Vec3 {
        let mx = rgb.max(), mn = rgb.min(), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == rgb.x { h = (rgb.y - rgb.z) / d }
            else if mx == rgb.y { h = 2 + (rgb.z - rgb.x) / d }
            else { h = 4 + (rgb.x - rgb.y) / d }
            h *= 60
            if h < 0 { h += 360 }
        }
        return Vec3(h, mx == 0 ? 0 : d / mx, mx)
    }

    static func hsvToRGB(_ hsv: Vec3) -> Vec3 {
        let h = (hsv.x.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = hsv.z * hsv.y
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = hsv.z - c
        let base: Vec3
        switch Int(h) {
        case 0: base = Vec3(c, x, 0)
        case 1: base = Vec3(x, c, 0)
        case 2: base = Vec3(0, c, x)
        case 3: base = Vec3(0, x, c)
        case 4: base = Vec3(x, 0, c)
        default: base = Vec3(c, 0, x)
        }
        return base + Vec3(repeating: m)
    }

    /// CIEDE2000 colour difference (Sharma, Wu, Dalal 2005), kL = kC = kH = 1.
    static func deltaE2000(_ l1: Vec3, _ l2: Vec3) -> Double {
        let rad = Double.pi / 180
        let c1 = hypot(l1.y, l1.z), c2 = hypot(l2.y, l2.z)
        let cBar = (c1 + c2) / 2
        let g = 0.5 * (1 - sqrt(pow(cBar, 7) / (pow(cBar, 7) + pow(25.0, 7))))
        let a1 = (1 + g) * l1.y, a2 = (1 + g) * l2.y
        let cp1 = hypot(a1, l1.z), cp2 = hypot(a2, l2.z)
        func hue(_ b: Double, _ a: Double) -> Double {
            if a == 0 && b == 0 { return 0 }
            let h = atan2(b, a) / rad
            return h < 0 ? h + 360 : h
        }
        let hp1 = hue(l1.z, a1), hp2 = hue(l2.z, a2)
        let dL = l2.x - l1.x, dC = cp2 - cp1
        var dh = 0.0
        if cp1 * cp2 != 0 {
            dh = hp2 - hp1
            if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        }
        let dH = 2 * sqrt(cp1 * cp2) * sin(dh / 2 * rad)
        let lBar = (l1.x + l2.x) / 2, cpBar = (cp1 + cp2) / 2
        var hBar = hp1 + hp2
        if cp1 * cp2 != 0 {
            if abs(hp1 - hp2) > 180 { hBar += hp1 + hp2 < 360 ? 360 : -360 }
            hBar /= 2
        }
        let t = 1 - 0.17 * cos((hBar - 30) * rad) + 0.24 * cos(2 * hBar * rad)
            + 0.32 * cos((3 * hBar + 6) * rad) - 0.20 * cos((4 * hBar - 63) * rad)
        let dTheta = 30 * exp(-pow((hBar - 275) / 25, 2))
        let rc = 2 * sqrt(pow(cpBar, 7) / (pow(cpBar, 7) + pow(25.0, 7)))
        let sl = 1 + 0.015 * pow(lBar - 50, 2) / sqrt(20 + pow(lBar - 50, 2))
        let sc = 1 + 0.045 * cpBar, sh = 1 + 0.015 * cpBar * t
        let rt = -sin(2 * dTheta * rad) * rc
        let x = dL / sl, y = dC / sc, z = dH / sh
        return sqrt(x * x + y * y + z * z + rt * y * z)
    }
}
