import Foundation

enum CSVAnimalImporter {

    struct Result {
        var rows: [ParsedAnimalRow]
        var mobNamesReferencedByFarmKey: [FarmLookupKey: Set<String>]
        var skippedRows: Int
    }

    struct ParsedAnimalRow {
        var eid: String

        // Per-row farm assignment fields
        var farmName: String?
        var farmPIC: String?

        var mobName: String?

        var sex: LocalDataStore.Sex?
        var status: AnimalStatus?

        /// Legacy single-value support. Kept for compatibility with existing callers.
        /// For historical / multi-year imports, prefer `lambsByYear`.
        var lambsPerYear: Int?

        /// New flexible yearly lambing data.
        /// Examples:
        /// - wide CSV: "Lambs 2023", "Lambs 2024"
        /// - narrow CSV: "Year", "Lambs"
        var lambsByYear: [Int: Int]

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

    struct HistoricalFleeceWeightResult {
        var rows: [ParsedHistoricalFleeceWeightRow]
        var skippedRows: Int
    }

    struct ParsedHistoricalFleeceWeightRow {
        var eid: String
        var fleeceWeightKg: Double
    }

    struct HistoricalStapleLengthResult {
        var rows: [ParsedHistoricalStapleLengthRow]
        var skippedRows: Int
    }

    struct ParsedHistoricalStapleLengthRow {
        var eid: String
        var stapleLengthMm: Double
    }

    // Lets LocalDataStore group mobs by either PIC or Farm Name
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
        let rows = cleanedCSVLines(from: csvText)

        guard !rows.isEmpty else {
            return Result(rows: [], mobNamesReferencedByFarmKey: [:], skippedRows: 0)
        }

        let firstRowRaw = parseCSVRow(rows[0])
        let normalizedFirstRow = firstRowRaw.map { normalizeHeader($0) }

        let hasHeader = rowLooksLikeHeader(normalizedFirstRow)

        let rawHeaders: [String]
        let normalizedHeaders: [String]
        let startIndex: Int

        if hasHeader {
            rawHeaders = firstRowRaw
            normalizedHeaders = normalizedFirstRow
            startIndex = 1
        } else {
            rawHeaders = [
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
            normalizedHeaders = rawHeaders.map { normalizeHeader($0) }
            startIndex = 0
        }

        let headerMap = HeaderMap(rawHeaders: rawHeaders, normalizedHeaders: normalizedHeaders)
        let wideLambYearColumns = detectWideLambYearColumns(rawHeaders: rawHeaders, normalizedHeaders: normalizedHeaders)

        var out: [ParsedAnimalRow] = []
        out.reserveCapacity(max(0, rows.count - startIndex))

        var skipped = 0
        var mobNamesByFarmKey: [FarmLookupKey: Set<String>] = [:]

        for i in startIndex..<rows.count {
            let cols = parseCSVRow(rows[i])

            guard let eidRaw = firstValue(["eid"], from: cols, using: headerMap) else {
                skipped += 1
                continue
            }

            let eid = EIDValidator.cleanedRaw(eidRaw)
            guard !eid.isEmpty, eid != "—" else {
                skipped += 1
                continue
            }

            let farmName = firstValue(["farm", "farmname"], from: cols, using: headerMap)
            let farmPIC = firstValue(["pic", "farmpic"], from: cols, using: headerMap)
            let mobName = firstValue(["mob", "mobname", "currentmob", "group"], from: cols, using: headerMap)

            let farmKey = FarmLookupKey(farmName: farmName, farmPIC: farmPIC)
            if let mobName, !mobName.isEmpty, !farmKey.isEmpty {
                mobNamesByFarmKey[farmKey, default: []].insert(mobName)
            }

            let fleece = parseDouble(firstValue(["fleeceweightkg", "fleeceweight", "fleecekg"], from: cols, using: headerMap))
            let staple = parseDouble(firstValue(["staplelengthmm", "staplelength", "staplemm"], from: cols, using: headerMap))

            let sexText = firstValue(["sex", "gender"], from: cols, using: headerMap)
            let parsedSex = parseSex(from: sexText)

            let statusText = firstValue(["status", "animalstatus"], from: cols, using: headerMap)
            let parsedStatus = parseAnimalStatus(from: statusText)

            let classText = firstValue(["class", "animalclass", "klass"], from: cols, using: headerMap)
            let parsedClass = parseAnimalClass(from: classText)

            let comments = firstValue(["comments", "comment", "notes", "remarks"], from: cols, using: headerMap)
            let user1 = firstValue(["user1", "userfield1", "custom1"], from: cols, using: headerMap)
            let user2 = firstValue(["user2", "userfield2", "custom2"], from: cols, using: headerMap)

            let klass: String? = {
                if let s = classText?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
                if let ac = parsedClass { return ac.rawValue }
                return nil
            }()

            // -----------------------------------------------------
            // Lambing import support
            // Supports BOTH:
            // 1) wide columns, e.g. Lambs 2023 / Lambs 2024
            // 2) narrow columns, e.g. Year + Lambs
            // 3) legacy single value, e.g. lambsPerYear
            // -----------------------------------------------------

            var lambsByYear: [Int: Int] = [:]

            // Wide format: Lambs 2023, Lambs 2024, ...
            if !wideLambYearColumns.isEmpty {
                for entry in wideLambYearColumns {
                    guard let raw = cols[safe: entry.index] else { continue }
                    guard let lambValue = parseInt(raw) else { continue }
                    lambsByYear[entry.year] = lambValue
                }
            }

            // Narrow format: Year + Lambs
            if let year = parseInt(firstValue(["year", "pregyear", "testyear"], from: cols, using: headerMap)) {
                if let lambValue = parseInt(firstValue(["lambnumber", "lamb", "lambs", "lambno", "numberoflambs", "lambcount", "pregresult"], from: cols, using: headerMap)) {
                    lambsByYear[year] = lambValue
                }
            }

            // Legacy / single current value
            let lambsPerYear = parseInt(firstValue(["lambsperyear", "lpy"], from: cols, using: headerMap))

            let row = ParsedAnimalRow(
                eid: eid,
                farmName: farmName,
                farmPIC: farmPIC,
                mobName: mobName,
                sex: parsedSex,
                status: parsedStatus,
                lambsPerYear: lambsPerYear,
                lambsByYear: lambsByYear,
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
    private static func parseSex(from text: String?) -> LocalDataStore.Sex? {
        guard let text else { return nil }

        let key = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        switch key {
        case "ewe", "female":
            return .ewe
        case "wether", "wtr":
            return .wether
        case "ram", "male":
            return .ram
        default:
            return nil
        }
    }

    private static func parseAnimalStatus(from text: String?) -> AnimalStatus? {
        guard let text else { return nil }

        let key = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        switch key {
        case "dry":
            return .dry
        case "pregnant", "preg":
            return .pregnant
        default:
            return nil
        }
    }

    // =========================================================
    // MARK: - Historical Preg CSV
    // =========================================================

    static func parseHistoricalPregCSV(csvText: String) -> HistoricalPregResult {
        let rows = cleanedCSVLines(from: csvText)

        guard !rows.isEmpty else {
            return HistoricalPregResult(rows: [], skippedRows: 0)
        }

        let firstRowRaw = parseCSVRow(rows[0])
        let normalizedFirstRow = firstRowRaw.map { normalizeHeader($0) }
        let hasHeader = rowLooksLikeHeader(normalizedFirstRow)

        let rawHeaders: [String]
        let normalizedHeaders: [String]
        let startIndex: Int

        if hasHeader {
            rawHeaders = firstRowRaw
            normalizedHeaders = normalizedFirstRow
            startIndex = 1
        } else {
            rawHeaders = ["eid", "year", "lambnumber"]
            normalizedHeaders = rawHeaders.map { normalizeHeader($0) }
            startIndex = 0
        }

        let headerMap = HeaderMap(rawHeaders: rawHeaders, normalizedHeaders: normalizedHeaders)
        let wideLambYearColumns = detectWideLambYearColumns(rawHeaders: rawHeaders, normalizedHeaders: normalizedHeaders)

        var out: [ParsedHistoricalPregRow] = []
        out.reserveCapacity(max(0, rows.count - startIndex))

        var skipped = 0

        for i in startIndex..<rows.count {
            let cols = parseCSVRow(rows[i])

            guard let eidRaw = firstValue(["eid"], from: cols, using: headerMap) else {
                skipped += 1
                continue
            }

            let eid = EIDValidator.cleanedRaw(eidRaw)
            guard !eid.isEmpty, eid != "—" else {
                skipped += 1
                continue
            }

            // Support wide format by expanding one row into multiple historical preg rows.
            if !wideLambYearColumns.isEmpty {
                var appendedAny = false

                for entry in wideLambYearColumns {
                    guard let raw = cols[safe: entry.index] else { continue }
                    guard let lambValue = parseInt(raw) else { continue }

                    out.append(
                        ParsedHistoricalPregRow(
                            eid: eid,
                            year: entry.year,
                            lambNumber: lambValue
                        )
                    )
                    appendedAny = true
                }

                if !appendedAny {
                    skipped += 1
                }
                continue
            }

            // Narrow format: Year + Lambs
            guard let year = parseInt(firstValue(["year", "pregyear", "testyear"], from: cols, using: headerMap)) else {
                skipped += 1
                continue
            }

            let lambNumber = parseInt(firstValue(["lambnumber", "lamb", "lambs", "lambno", "pregresult", "numberoflambs", "lambcount"], from: cols, using: headerMap))

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

    static func parseHistoricalFleeceWeightCSV(csvText: String) -> HistoricalFleeceWeightResult {
        let rows = cleanedCSVLines(from: csvText)

        guard !rows.isEmpty else {
            return HistoricalFleeceWeightResult(rows: [], skippedRows: 0)
        }

        let firstRowRaw = parseCSVRow(rows[0])
        let normalizedFirstRow = firstRowRaw.map { normalizeHeader($0) }
        let hasHeader = rowLooksLikeHeader(normalizedFirstRow)

        let rawHeaders: [String]
        let normalizedHeaders: [String]
        let startIndex: Int

        if hasHeader {
            rawHeaders = firstRowRaw
            normalizedHeaders = normalizedFirstRow
            startIndex = 1
        } else {
            rawHeaders = ["eid", "fleeceweightkg"]
            normalizedHeaders = rawHeaders.map { normalizeHeader($0) }
            startIndex = 0
        }

        let headerMap = HeaderMap(rawHeaders: rawHeaders, normalizedHeaders: normalizedHeaders)

        var out: [ParsedHistoricalFleeceWeightRow] = []
        out.reserveCapacity(max(0, rows.count - startIndex))

        var skipped = 0

        for i in startIndex..<rows.count {
            let cols = parseCSVRow(rows[i])

            guard let eidRaw = firstValue(["eid", "rfid", "tag", "nlis"], from: cols, using: headerMap) else {
                skipped += 1
                continue
            }

            let eid = EIDValidator.cleanedRaw(eidRaw)
            guard !eid.isEmpty, eid != "—" else {
                skipped += 1
                continue
            }

            guard let fleeceWeightKg = parseDouble(firstValue(["fleeceweightkg", "fleeceweight", "fleecekg"], from: cols, using: headerMap)) else {
                skipped += 1
                continue
            }

            out.append(
                ParsedHistoricalFleeceWeightRow(
                    eid: eid,
                    fleeceWeightKg: fleeceWeightKg
                )
            )
        }

        return HistoricalFleeceWeightResult(
            rows: out,
            skippedRows: skipped
        )
    }

    static func parseHistoricalStapleLengthCSV(csvText: String) -> HistoricalStapleLengthResult {
        let rows = cleanedCSVLines(from: csvText)

        guard !rows.isEmpty else {
            return HistoricalStapleLengthResult(rows: [], skippedRows: 0)
        }

        let firstRowRaw = parseCSVRow(rows[0])
        let normalizedFirstRow = firstRowRaw.map { normalizeHeader($0) }
        let hasHeader = rowLooksLikeHeader(normalizedFirstRow)

        let rawHeaders: [String]
        let normalizedHeaders: [String]
        let startIndex: Int

        if hasHeader {
            rawHeaders = firstRowRaw
            normalizedHeaders = normalizedFirstRow
            startIndex = 1
        } else {
            rawHeaders = ["eid", "staplelengthmm"]
            normalizedHeaders = rawHeaders.map { normalizeHeader($0) }
            startIndex = 0
        }

        let headerMap = HeaderMap(rawHeaders: rawHeaders, normalizedHeaders: normalizedHeaders)

        var out: [ParsedHistoricalStapleLengthRow] = []
        out.reserveCapacity(max(0, rows.count - startIndex))

        var skipped = 0

        for i in startIndex..<rows.count {
            let cols = parseCSVRow(rows[i])

            guard let eidRaw = firstValue(["eid", "rfid", "tag", "nlis"], from: cols, using: headerMap) else {
                skipped += 1
                continue
            }

            let eid = EIDValidator.cleanedRaw(eidRaw)
            guard !eid.isEmpty, eid != "—" else {
                skipped += 1
                continue
            }

            guard let stapleLengthMm = parseDouble(firstValue(["staplelengthmm", "staplelength", "staplemm"], from: cols, using: headerMap)) else {
                skipped += 1
                continue
            }

            out.append(
                ParsedHistoricalStapleLengthRow(
                    eid: eid,
                    stapleLengthMm: stapleLengthMm
                )
            )
        }

        return HistoricalStapleLengthResult(
            rows: out,
            skippedRows: skipped
        )
    }

    // MARK: - Helpers

    private struct HeaderMap {
        let rawHeaders: [String]
        let normalizedHeaders: [String]

        func firstIndex(ofAny keys: [String]) -> Int? {
            for key in keys {
                if let idx = normalizedHeaders.firstIndex(of: key) {
                    return idx
                }
            }
            return nil
        }
    }

    private struct WideLambYearColumn {
        let index: Int
        let year: Int
    }

    private static func cleanedCSVLines(from csvText: String) -> [String] {
        csvText
            .split(whereSeparator: \.isNewline)
            .map {
                String($0)
                    .replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func rowLooksLikeHeader(_ normalizedRow: [String]) -> Bool {
        let headerSignals: Set<String> = [
            "eid",
            "farm",
            "pic",
            "mob",
            "class",
            "comments",
            "year",
            "lambnumber",
            "lambsperyear",
            "fleeceweightkg",
            "staplelengthmm",
            "user1",
            "user2"
        ]

        if normalizedRow.contains(where: { headerSignals.contains($0) }) {
            return true
        }

        // Also treat rows like "Lambs 2024" / "lambs_2025" as header rows.
        return normalizedRow.contains(where: { yearFromWideLambHeader($0) != nil })
    }

    private static func value(_ key: String, from cols: [String], using headerMap: HeaderMap) -> String? {
        guard let idx = headerMap.firstIndex(ofAny: [key]), let v = cols[safe: idx] else { return nil }
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func firstValue(_ keys: [String], from cols: [String], using headerMap: HeaderMap) -> String? {
        for key in keys {
            if let v = value(key, from: cols, using: headerMap) {
                return v
            }
        }
        return nil
    }

    private static func parseInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        let cleaned = t.filter { $0.isNumber || $0 == "-" }
        return cleaned.isEmpty ? nil : Int(cleaned)
    }

    private static func parseDouble(_ s: String?) -> Double? {
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

    private static func detectWideLambYearColumns(rawHeaders: [String], normalizedHeaders: [String]) -> [WideLambYearColumn] {
        var result: [WideLambYearColumn] = []

        for (index, rawHeader) in rawHeaders.enumerated() {
            let normalized = normalizedHeaders[safe: index] ?? normalizeHeader(rawHeader)
            if let year = yearFromWideLambHeader(rawHeader) ?? yearFromWideLambHeader(normalized) {
                result.append(WideLambYearColumn(index: index, year: year))
            }
        }

        return result.sorted { $0.year < $1.year }
    }

    private static func yearFromWideLambHeader(_ header: String) -> Int? {
        let lower = header
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Only treat it as a lamb-year column if the heading clearly references lambs/preg.
        let hasLambSignal =
            lower.contains("lamb") ||
            lower.contains("preg")

        guard hasLambSignal else { return nil }

        let digits = lower.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }

        // Prefer the last 4 digits so headers like "lambs_2024" or "preg result 2025"
        // work even if other digits appear earlier.
        let yearString = String(digits.suffix(4))
        guard let year = Int(yearString), (1900...2100).contains(year) else { return nil }
        return year
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

            // Sex
            case "sex", "gender":
                return "sex"

            // Status
            case "status", "animalstatus":
                return "status"

        // Class
        case "class", "currentclass", "animalclass", "klass":
            return "class"

            // Comments
            case "comments", "comment", "notes", "remarks":
                return "comments"

        // Lambs per year (legacy single value)
        case "lambsperyear", "lpy":
            return "lambsperyear"

        // Historical preg year
        case "year", "pregyear", "testyear":
            return "year"

        // Historical preg lamb number
        case "lambnumber", "lamb", "lambs", "numberoflambs", "lambcount", "pregresult", "lambno":
            return "lambnumber"

        // Fleece weight
        case "fleeceweight", "fleeceweightkg", "fleecekg":
            return "fleeceweightkg"

        // Staple
        case "staplelength", "staplelengthmm", "staplemm":
            return "staplelengthmm"

        // User custom fields
        case "user1", "userfield1", "custom1":
            return "user1"

        case "user2", "userfield2", "custom2":
            return "user2"

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
