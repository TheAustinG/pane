import Foundation

/// Björn Ottosson's OKLab: perceptually even, so equal steps read as equal color changes and
/// blends between anchors do not dip through muddy greys the way sRGB blends do.
struct OKLab: Hashable, Sendable {
    var l: Double
    var a: Double
    var b: Double

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ rgb: RGB) {
        let r = Self.linear(rgb.red)
        let g = Self.linear(rgb.green)
        let bl = Self.linear(rgb.blue)
        let lms = (
            cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl),
            cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl),
            cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        )
        l = 0.2104542553 * lms.0 + 0.7936177850 * lms.1 - 0.0040720468 * lms.2
        a = 1.9779984951 * lms.0 - 2.4285922050 * lms.1 + 0.4505937099 * lms.2
        b = 0.0259040371 * lms.0 + 0.7827717662 * lms.1 - 0.8086757660 * lms.2
    }

    var rgb: RGB {
        let l1 = l + 0.3963377774 * a + 0.2158037573 * b
        let m1 = l - 0.1055613458 * a - 0.0638541728 * b
        let s1 = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l1 * l1 * l1
        let m3 = m1 * m1 * m1
        let s3 = s1 * s1 * s1
        return RGB(
            red: Self.encoded(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
            green: Self.encoded(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
            blue: Self.encoded(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
        )
    }

    func mixed(with other: OKLab, _ t: Double) -> OKLab {
        OKLab(l: l + (other.l - l) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }

    func distance(to other: OKLab) -> Double {
        let dl = l - other.l
        let da = a - other.a
        let db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ c: Double) -> Double {
        let c = min(max(c, 0), 1)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

extension RGB {
    /// Blends toward `other` in OKLab.
    public func interpolated(to other: RGB, fraction: Double) -> RGB {
        OKLab(self).mixed(with: OKLab(other), fraction).rgb
    }

    /// Euclidean distance in OKLab. About 0.02 is a just-noticeable difference.
    public func distance(to other: RGB) -> Double {
        OKLab(self).distance(to: OKLab(other))
    }
}
