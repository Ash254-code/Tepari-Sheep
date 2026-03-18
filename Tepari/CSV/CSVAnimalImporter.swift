import Foundation

enum CSVAnimalImporter {

    struct Result {
        var rows: [ParsedAnimalRow]
        var mobNamesReferencedByFarmKey: [FarmLookupKey: Set<String>]
        var skippedRows: Int
    }

    struct ParsedAnimalRow {
        var eid: String

        // ✅ NEW: per-row farm assignment fields
        var farmName: String?
        var farmPIC: String?

        var mobName: String?
        var lambsPerYear: Int?
        var fleeceWeightKg: Double?
        var stapleLengthMm: Double?
        var animalClass: LocalDataStore.AnimalClass?
        var klass: String?
        var comments: String?
        var userField1: String?
        var userField2: String?
    }

    // =========================================================
    // MARK: - Historical Preg Import
    // =========================================================

    struct HistoricalPregResult {
        var rows: [ParsedHistoricalPregRow]
        var skippedRows: Int
    }

    struct ParsedHistoricalPregRow {
        var eid: String
        var year: Int
        var lambNumber: Int?
    }

    // ✅ NEW: lets LocalDataStore group mobs by either PIC or Farm Name
    struct FarmLookupKey: Hashable {
        var farmName: String?
        var farmPIC: String?

        init(farmName: String?, farmPIC: String?) {
            let trimmedFarm = farmName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPIC = farmPIC?.trimmingCharacters(in: .whitespacesAndNewlines)

            self.farmName = (trimmedFarm?.isEmpty == false) ? trimmedFarm : nil
            self.farmPIC = (trimmedPIC?.isEmpty == false) ? trimmedPIC : nil
        }

        var isEmpty: Bool {
            farmName == nil && farmPIC == nil
        }
    }

    // MARK: - Public API

    static func parseAnimalsCSV(csvText: String) -> Result {

        let rows = csvText
            .split(whereSeparator: \.isNewline)
            .map { String($0).replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rows.isEmpty else {
            return Result(rows: [], mobNamesReferencedByFarmKey: [:], skippedRows: 0)
        }

        let firstRow = parseCSVRow(rows[0]).map { normalizeHeader($0) }
        let hasHeader = firstRow.contains("eid")

        let headers: [String]
        let startIndex: Int
        if hasHeader {
            headers = firstRow
            startIndex = 1
        } else {
            headers = [
                "eid",
                "farm",
                "pic",
                "mob",
                "lambsperyear",
                "fleeceweightkg",
                "staplelengthmm",
                "class",
                "comments",
                "user1",
                "user2"
            ]
            startIndex = 0
        }

        func value(_ key: String, from cols: [String]) -> String? {
            guard let idx = headers.firstIndex(of: key), let v = cols[safe: idx] else { return nil }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        func firstValue(_ keys: [String], from cols: [String]) -> String? {
            for key in keys {
                if let v = value(key, from: cols) { return v }
            }
            return nil
        }

        func parseInt(_ s: String?) -> Int? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }

            let cleaned = t.filter { $0.isNumber || $0 == "-" }
            return cleaned.isEmpty ? nil : Int(cleaned)
        }

        func parseDouble(_ s: String?) -> Double? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }

            var cleaned = t.filter { $0.isNumber || $0 == "." || $0 == "-" || $0 == "," }

            if cleaned.contains(",") && !cleaned.contains(".") {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }

            return cleaned.isEmpty ? nil : Double(cleaned)
        }

        var out: [ParsedAnimalRow] = []
        out.reserveCapacity(max(0, rows.count - startIndex))

        var skipped = 0
        var mobNamesByFarmKey: [FarmLookupKey: Set<String>] = [:]

        for i in startIndex..<rows.count {
            let cols = parseCSVRow(rows[i])

            guard let eidRaw = value("eid", from: cols) else {
                skipped += 1
                continue
            }

            let eid = EIDValidator.cleanedRaw(eidRaw)
            guard !eid.isEmpty, eid != "—" else {
                skipped += 1
                continue
            }

            let farmName = firstValue(["farm", "farmname"], from: cols)
            let farmPIC = firstValue(["pic", "farmpic"], from: cols)

            let farmKey = FarmLookupKey(farmName: farmName, farmPIC: farmPIC)

            let mobName = value("mob", from: cols)
            if let mobName, !mobName.isEmpty, !farmKey.isEmpty {
                mobNamesByFarmKey[farmKey, default: []].insert(mobName)
            }

            let lambs = parseInt(value("lambsperyear", from: cols))
            let fleece = parseDouble(value("fleeceweightkg", from: cols))
            let staple = parseDouble(value("staplelengthmm", from: cols))

            let classText = value("class", from: cols)
            let parsedClass = parseAnimalClass(from: classText)

            let comments = value("comments", from: cols)
            let user1 = value("user1", from: cols)
            let user2 = value("user2", from: cols)

            let klass: String? = {
                if let s = classText?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
                if let ac = parsedClass { return ac.rawValue }
                return nil
            }()

            let row = ParsedAnimalRow(
                eid: eid,
                farmName: farmName,
                farmPIC: farmPIC,
                mobName: mobName,
                lambsPerYear: lambs,
                fleeceWeightKg: fleece,
                stapleLengthMm: staple,
                animalClass: parsedClass,
                klass: klass,
                comments: comments,
                userField1: user1,
                userField2: user2
            )

            out.append(row)
        }

        return Result(
            rows: out,
            mobNamesReferencedByFarmKey: mobNamesByFarmKey,
            skippedRows: skipped
        )
    }

    // =========================================================
    // MARK: - Historical Preg CSV
    // =========================================================

    static func parseHistoricalPregCSV(csvText: String) -> HistoricalPregResult {

        let rows = csvText
            .split(whereSeparator: \.isNewline)
            .map { String($0).replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rows.isEmpty else {
            return HistoricalPregResult(rows: [], skippedRows: 0)
        }

        let firstRow = parseCSVRow(rows[0]).map { normalizeHeader($0) }
        let hasHeader = firstRow.contains("eid") || firstRow.contains("year") || firstRow.contains("lambnumber")

        let headers: [String]
        let startIndex: Int
        if hasHeader {
            headers = firstRow
            startIndex = 1
        } else {
            headers = ["eid", "year", "lambnumber"]
            startIndex = 0
        }

        func value(_ key: String, from cols: [String]) -> String? {
            guard let idx = headers.firstIndex(of: key), let v = cols[safe: idx] else { return nil }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        func firstValue(_ keys: [String], from cols: [String]) -> String? {
            for key in keys {
                if let v = value(key, from: cols) { return v }
            }
            return nil
        }

        func parseInt(_ s: String?) -> Int? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }

            let cleaned = t.filter { $0.isNumber || $0 == "-" }
            return cleaned.isEmpty ? nil : Int(cleaned)
        }

        var out: [ParsedHistoricalPregRow] = []
        out.reserveCapacity(max(0, rows.count - startIndex))

        var skipped = 0

        for i in startIndex..<rows.count {
            let cols = parseCSVRow(rows[i])

            guard let eidRaw = firstValue(["eid"], from: cols) else {
                skipped += 1
                continue
            }

            let eid = EIDValidator.cleanedRaw(eidRaw)
            guard !eid.isEmpty, eid != "—" else {
                skipped += 1
                continue
            }

            guard let year = parseInt(firstValue(["year"], from: cols)) else {
                skipped += 1
                continue
            }

            let lambNumber = parseInt(firstValue(["lambnumber", "lamb", "lambs", "lambno", "pregresult"], from: cols))

            out.append(
                ParsedHistoricalPregRow(
                    eid: eid,
                    year: year,
                    lambNumber: lambNumber
                )
            )
        }

        return HistoricalPregResult(
            rows: out,
            skippedRows: skipped
        )
    }

    // MARK: - CSV parsing

    private static func parseCSVRow(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false

        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if c == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    cur.append("\"")
                    i += 2
                    continue
                } else {
                    inQuotes.toggle()
                    i += 1
                    continue
                }
            }

            if c == "," && !inQuotes {
                out.append(cur)
                cur = ""
                i += 1
                continue
            }

            cur.append(c)
            i += 1
        }

        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func normalizeHeader(_ s: String) -> String {

        let key = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")

        switch key {

        // RFID / EID
        case "eid", "rfid", "tag", "tagid", "eartag", "eartagid", "nlis", "nlisid":
            return "eid"

        // Farm name
        case "farm", "farmname", "property", "propertyname":
            return "farm"

        // PIC
        case "pic", "farmpic", "propertypic":
            return "pic"

        // Mob
        case "mob", "currentmob", "mobname", "group":
            return "mob"

        // Class
        case "class", "currentclass", "animalclass", "klass":
            return "class"

        // Comments
        case "comments", "comment", "notes":
            return "comments"

        // Lambs per year
        case "lambsperyear", "lpy":
            return "lambsperyear"

        // Historical preg year
        case "year", "pregyear", "testyear":
            return "year"

        // Historical preg lamb number
        case "lambnumber", "lamb", "lambs", "numberoflambs", "lambcount", "pregresult":
            return "lambnumber"

        // Fleece weight
        case "fleeceweight", "fleeceweightkg", "fleecekg":
            return "fleeceweightkg"

        // Staple
        case "staplelength", "staplelengthmm", "staplemm":
            return "staplelengthmm"

        default:
            return key
        }
    }

    private static func parseAnimalClass(from text: String?) -> LocalDataStore.AnimalClass? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        let key = t.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        if let direct = LocalDataStore.AnimalClass(rawValue: key) { return direct }

        switch key {
        case "studreserve", "studres", "reserve":
            return .studReserve
        case "flock", "mainflock":
            return .flock
        case "cull", "culls":
            return .cull
        case "stud", "ramstud":
            return .stud
        default:
            return nil
        }
    }
}

// MARK: - Safe indexing helper (local to this file)

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
