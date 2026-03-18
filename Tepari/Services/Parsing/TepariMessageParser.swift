import Foundation

final class TepariMessageParser {

    func parseLine(_ line: String) -> [TepariEvent] {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }

        // ignore app logs
        if s.hasPrefix("[") { return [] }

        var out: [TepariEvent] = []

        let weight = matchWeight(s)
        let eid = matchEID(s)
        let stable = matchStable(s)

        let upper = s.uppercased()
        let isLabelledEIDLine =
            upper.contains("EID") ||
            upper.contains("RFID") ||
            upper.contains("TAG")

        // Treat labelled EID-only lines as debug/noise.
        // Real scan events should come from combined weight+EID lines.
        if let weight {
            out.append(.weight(weight))

            if let eid {
                out.append(.eid(eid))
            }
        } else {
            // Only allow standalone EID if it is NOT a labelled debug line
            if let eid, !isLabelledEIDLine {
                out.append(.eid(eid))
            }
        }

        if let stable {
            out.append(.stable(stable))
        }

        return out
    }

    // MARK: - EID

    private func matchEID(_ s: String) -> String? {
        let u = s.uppercased()

        // 1) If it's a labelled EID/RFID/TAG line, try to format from all digits found
        if u.contains("EID") || u.contains("RFID") || u.contains("TAG") {
            let digits = s.filter(\.isNumber)
            return formattedEID(fromDigits: digits)
        }

        // 2) Prefer legacy format already split as "982 123826571661"
        let spacedPattern = #"\b(982)\s+(\d{12})\b"#
        if let re = try? NSRegularExpression(pattern: spacedPattern) {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)

            if let match = re.firstMatch(in: s, options: [], range: range),
               match.numberOfRanges >= 3 {
                let prefix = ns.substring(with: match.range(at: 1))
                let rest = ns.substring(with: match.range(at: 2))
                return "\(prefix) \(rest)"
            }
        }

        // 3) Look for a continuous 15-digit NLIS starting with 982
        let fullPattern = #"\b(982\d{12})\b"#
        if let re = try? NSRegularExpression(pattern: fullPattern) {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)

            if let match = re.firstMatch(in: s, options: [], range: range),
               match.numberOfRanges >= 2 {
                let candidate = ns.substring(with: match.range(at: 1))
                return formattedEID(fromDigits: candidate)
            }
        }

        // 4) Fallback: plain 12-digit tag body, re-add legacy prefix for consistency
        let shortPattern = #"\b(\d{12})\b"#
        if let re = try? NSRegularExpression(pattern: shortPattern) {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)

            if let match = re.firstMatch(in: s, options: [], range: range),
               match.numberOfRanges >= 2 {
                let candidate = ns.substring(with: match.range(at: 1))
                return formattedEID(fromDigits: candidate)
            }
        }

        return nil
    }

    private func formattedEID(fromDigits digits: String) -> String? {
        let cleaned = digits.filter(\.isNumber)

        if cleaned.count == 15, cleaned.hasPrefix("982") {
            return "982 \(cleaned.dropFirst(3))"
        }

        if cleaned.count == 12 {
            return "982 \(cleaned)"
        }

        return nil
    }

    // MARK: - Weight

    private func matchWeight(_ s: String) -> Double? {
        let u = s.uppercased()

        let labelledPatterns = [
            #"(?:\bWT\b|\bW\b|\bWEIGHT\b)\s*[:=]?\s*(-?\d{1,5}(?:\.\d{1,3})?)"#,
            #"(?:\bKG\b|\bKGS\b)\s*[:=]?\s*(-?\d{1,5}(?:\.\d{1,3})?)"#,
            #"(?:\bLB\b|\bLBS\b)\s*[:=]?\s*(-?\d{1,5}(?:\.\d{1,3})?)"#
        ]

        for p in labelledPatterns {
            if let v = firstCapture(in: s, pattern: p) {
                return v
            }
        }

        let looksWeightish =
            u.contains("KG") ||
            u.contains("LB") ||
            u.contains("WT") ||
            u.contains("WEIGHT") ||
            u.contains("W:")

        if looksWeightish {
            if let v = firstNumber(in: s) {
                let digitsOnly = String(v).filter(\.isNumber)
                if digitsOnly.count >= 12 { return nil }
                return Double(v)
            }
        }

        let decPattern = #"(-?\d{1,5}\.\d{1,3})"#
        if let r = s.range(of: decPattern, options: .regularExpression) {
            let candidate = String(s[r])
            let digitsOnly = candidate.filter(\.isNumber)
            if digitsOnly.count >= 12 { return nil }
            return Double(candidate)
        }

        return nil
    }

    private func firstCapture(in s: String, pattern: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: s, options: [], range: range) else { return nil }
        guard m.numberOfRanges >= 2 else { return nil }
        let cap = ns.substring(with: m.range(at: 1))
        return Double(cap)
    }

    private func firstNumber(in s: String) -> String? {
        let numPattern = #"(-?\d{1,5}(?:\.\d{1,3})?)"#
        if let r = s.range(of: numPattern, options: .regularExpression) {
            return String(s[r])
        }
        return nil
    }

    // MARK: - Stable

    private func matchStable(_ s: String) -> Bool? {
        let u = s.uppercased()

        if u.contains("UNSTABLE") { return false }
        if u == "STABLE" { return true }

        if u.contains("MOTION") && u.range(of: #"MOTION\s*[:=]?\s*0"#, options: .regularExpression) != nil { return true }
        if u.contains("MOTION") && u.range(of: #"MOTION\s*[:=]?\s*1"#, options: .regularExpression) != nil { return false }

        let patternsTrue = [
            #"STABLE\s*[:=]?\s*1"#,
            #"STB\s*[:=]?\s*1"#,
            #"ST\s*[:=]?\s*1"#,
            #"S\s*[:=]?\s*1"#,
            #"LOCK(?:ED)?\s*[:=]?\s*1"#,
            #"\bOK\b"#
        ]

        for p in patternsTrue {
            if u.range(of: p, options: .regularExpression) != nil { return true }
        }

        let patternsFalse = [
            #"STABLE\s*[:=]?\s*0"#,
            #"STB\s*[:=]?\s*0"#,
            #"ST\s*[:=]?\s*0"#,
            #"S\s*[:=]?\s*0"#,
            #"LOCK(?:ED)?\s*[:=]?\s*0"#
        ]

        for p in patternsFalse {
            if u.range(of: p, options: .regularExpression) != nil { return false }
        }

        if u.contains("STABLE") {
            if u.range(of: #"\b1\b"#, options: .regularExpression) != nil { return true }
            if u.range(of: #"\b0\b"#, options: .regularExpression) != nil { return false }
        }

        return nil
    }
}
