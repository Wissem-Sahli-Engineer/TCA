import Foundation

// JSON shapes returned by backend/backend.py. The API client decodes with
// .convertFromSnakeCase, so `given_name` arrives as `givenName`. Dates are
// kept as the API's "YYYY-MM-DD" strings.

struct User: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let email: String
    let role: String
    let status: String

    var isAdmin: Bool { role == "Admin" }
}

struct LoginResponse: Decodable {
    let token: String
    let user: User
}

struct MessageResponse: Decodable {
    let status: String?
    let message: String?
}

struct Client: Codable, Identifiable, Hashable {
    let id: Int
    var givenName: String
    var surname: String
    var passportNumber: String
    var country: String?
    var nationality: String?
    var type: String?
    var sex: String?
    var dateOfBirth: String?
    var placeOfBirth: String?
    var dateOfIssue: String?
    var dateOfExpiry: String?
    var issuedBy: String?
    var phone: String?
    var email: String?
    var entrepriseName: String?
    var codeFiscal: String?
    var category: String?
    var fairEmail: String?
    var visaStatus: String?
    var visaType: String?
    var visaTypeOther: String?
    var prixDossier: Double?
    var paiementType: String?
    var paymentState: String?
    var currency: String?
    var hasFlight: Bool?
    var flightDate: String?
    var destination: String?
    var airlineName: String?
    var hotelReservation: Bool?
    var hotelName: String?
    var duration: String?
    var reservationAmount: Double?
    var userPhoto: String?
    var passportImage: String?
    var createdBy: String?
    var createdAt: String?

    var fullName: String { "\(givenName) \(surname)" }
    /// A client without a status is treated as a new file.
    var visa: VisaStatus { visaStatus.flatMap(VisaStatus.init(rawValue:)) ?? .new }
    var clientCategory: ClientCategory { category.flatMap(ClientCategory.init(rawValue:)) ?? .normal }
    var payment: PaymentState? { paymentState.flatMap(PaymentState.init(rawValue:)) }

    /// Why the client is in alert (Alert tab, bell); empty when not.
    /// Same rules as alertReasons() in src/features/clients/options.js.
    var alertReasons: [AlertReason] {
        var reasons: [AlertReason] = []
        if visa == .passportReady { reasons.append(.passportReady) }
        if hasFlight == true, let flightDate, !visa.isTreated,
           let flight = Fmt.apiDate.date(from: flightDate) {
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: flight)).day ?? -1
            if (0...AlertReason.tripDays).contains(days) { reasons.append(.tripSoon(date: flightDate)) }
        }
        return reasons
    }

    var isAlert: Bool { !alertReasons.isEmpty }

    /// Which of the agency's two countries the client belongs to, from the
    /// passport country (else nationality); nil when neither.
    var countryGroup: Country? { Country.detect(country) ?? Country.detect(nationality) }

    /// The client's own photo, else their passport scan.
    var displayPhoto: String? {
        [userPhoto, passportImage].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// Visa type label, including the free text when it's "other".
    var visaTypeLabel: String {
        guard let visaType, !visaType.isEmpty else { return "" }
        let label = VisaType(rawValue: visaType)?.label ?? visaType
        if visaType == VisaType.other.rawValue, let detail = visaTypeOther, !detail.isEmpty {
            return "\(label): \(detail)"
        }
        return label
    }

    /// Value of a form field by its API key (see ClientFields).
    func value(for key: String) -> String {
        switch key {
        case "country": return country ?? ""
        case "passport_number": return passportNumber
        case "type": return type ?? ""
        case "nationality": return nationality ?? ""
        case "given_name": return givenName
        case "surname": return surname
        case "date_of_birth": return dateOfBirth ?? ""
        case "sex": return sex ?? ""
        case "place_of_birth": return placeOfBirth ?? ""
        case "date_of_issue": return dateOfIssue ?? ""
        case "date_of_expiry": return dateOfExpiry ?? ""
        case "issued_by": return issuedBy ?? ""
        case "phone": return phone ?? ""
        case "email": return email ?? ""
        case "entreprise_name": return entrepriseName ?? ""
        case "code_fiscal": return codeFiscal ?? ""
        case "category": return category ?? "normal"
        case "fair_email": return fairEmail ?? ""
        case "visa_status": return visaStatus ?? ""
        case "visa_type": return visaType ?? ""
        case "visa_type_other": return visaTypeOther ?? ""
        case "prix_dossier": return prixDossier.map { Fmt.num($0).replacingOccurrences(of: ",", with: "") } ?? ""
        case "paiement_type": return paiementType ?? ""
        case "payment_state": return paymentState ?? ""
        case "currency": return currency ?? ""
        case "has_flight": return hasFlight == true ? "true" : "false"
        case "flight_date": return flightDate ?? ""
        case "destination": return destination ?? ""
        case "airline_name": return airlineName ?? ""
        case "hotel_reservation": return hotelReservation == true ? "true" : "false"
        case "hotel_name": return hotelName ?? ""
        case "duration": return duration ?? ""
        case "reservation_amount": return reservationAmount.map { Fmt.num($0).replacingOccurrences(of: ",", with: "") } ?? ""
        default: return ""
        }
    }
}

/// Field keys in the same order as src/features/clients/fields.js.
enum ClientFields {
    static let passport = [
        "country", "passport_number", "type", "nationality", "given_name", "surname",
        "date_of_birth", "sex", "place_of_birth", "date_of_issue", "date_of_expiry", "issued_by",
    ]
    static let business = [
        "phone", "email", "entreprise_name", "code_fiscal", "prix_dossier",
    ]
    /// Pick-list, travel and reservation fields (rendered individually).
    static let choices = [
        "category", "fair_email", "visa_status", "visa_type", "visa_type_other",
        "paiement_type", "payment_state", "currency",
        "has_flight", "flight_date", "destination",
        "airline_name", "hotel_reservation", "hotel_name", "duration", "reservation_amount",
    ]
    static let all = passport + business + choices
}

struct ClientSaveResponse: Decodable {
    let client: Client
}

struct ClientFile: Codable, Identifiable, Hashable {
    let id: Int
    let filename: String
    let contentType: String?
    let uploadedAt: String?
    let url: String
}

struct ExtractResult: Decodable {
    var country: String?
    var passportNumber: String?
    var type: String?
    var nationality: String?
    var givenName: String?
    var surname: String?
    var dateOfBirth: String?
    var sex: String?
    var placeOfBirth: String?
    var dateOfIssue: String?
    var dateOfExpiry: String?
    var issuedBy: String?
    var userPhoto: String?

    var fields: [String: String] {
        [
            "country": country, "passport_number": passportNumber, "type": type,
            "nationality": nationality, "given_name": givenName, "surname": surname,
            "date_of_birth": dateOfBirth, "sex": sex, "place_of_birth": placeOfBirth,
            "date_of_issue": dateOfIssue, "date_of_expiry": dateOfExpiry, "issued_by": issuedBy,
        ].mapValues { $0 ?? "" }
    }
}

// MARK: Treasury

struct TreasuryEntry: Codable, Identifiable, Hashable {
    let id: Int
    let country: String
    let kind: String
    let productName: String
    let price: Double
    let entryDate: String
    let recordedBy: String?
    let counterparty: String?
}

struct TreasuryMonth: Codable, Hashable, Identifiable {
    let month: String
    var spending: Double
    var gathering: Double
    var net: Double?

    var id: String { month }
}

struct TreasuryCurrentMonth: Codable {
    let month: String
    let spending: Double
    let gathering: Double
    let net: Double
    let entries: [TreasuryEntry]
}

struct TreasuryResponse: Codable {
    let currentMonth: TreasuryCurrentMonth
    let history: [TreasuryMonth]
}

struct NewTreasuryEntry: Encodable {
    let country: String
    let kind: String
    let productName: String
    let price: Double
    let entryDate: String
    let recordedBy: String?
    let counterparty: String?
}

// MARK: Banking

struct BankAccount: Codable, Identifiable, Hashable {
    let id: Int
    let country: String
    let name: String
    let currency: String
    let balance: Double
}

struct NewBankAccount: Encodable {
    let country: String
    let name: String
    let currency: String
    let balance: Double
}

struct BankTransaction: Codable, Identifiable, Hashable {
    let id: Int
    let accountId: Int
    let label: String
    let amount: Double
    let entryDate: String
}

struct NewBankTransaction: Encodable {
    let accountId: Int
    let label: String
    let amount: Double
    let entryDate: String
}

// MARK: Invoices

struct InvoiceItem: Codable, Hashable {
    var designation: String
    var quantity: Double
    var unitPrice: Double
}

struct Invoice: Codable, Identifiable, Hashable {
    let id: Int
    let country: String
    let docType: String
    let clientName: String
    let clientPassport: String?
    let clientMf: String?
    let companyName: String?
    let serviceType: String?
    let issueDate: String
    let tvaRate: Double
    let timbre: Double
    let amountPaid: Double
    let items: [InvoiceItem]
    let number: String
    let pdfUrl: String
}

struct NewInvoice: Encodable {
    let country: String
    let docType: String
    let clientName: String
    let clientPassport: String?
    let clientMf: String?
    let companyName: String?
    let serviceType: String?
    let issueDate: String
    let tvaRate: Double
    let timbre: Double
    let amountPaid: Double
    let items: [InvoiceItem]
}

// MARK: Requests

struct AgencyRequest: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String
    let submittedDate: String
    let status: String
}

struct NewAgencyRequest: Encodable {
    let name: String
    let description: String
    let submittedDate: String
}

struct EmployeeRequest: Codable, Identifiable, Hashable {
    let id: Int
    let category: String
    let employeeName: String
    let detail: String
    let submittedDate: String
    let status: String
    /// Who submitted it; they (and the admin) can remove it.
    let userEmail: String?
}

struct NewEmployeeRequest: Encodable {
    let category: String
    let employeeName: String
    let detail: String
    let submittedDate: String
}

// MARK: Payroll

/// One day of a ZKTeco K40 time-clock export, as returned by
/// /payroll/parse-pointage and sent back unchanged to compute the payslip.
struct PointageDay: Codable, Hashable {
    let date: String
    let hor: String
    let deb: String
    let fin: String
    let ent: String
    let sor: String
    let hsup: String
    let reel: String
    let plan: String
    let absent: Bool
    let we: Bool
    let hol: Bool
}

/// One employee found in the export (a file may hold several).
struct PointageEmployee: Codable, Hashable, Identifiable {
    let empNo: String
    let employeeName: String
    let matricule: String
    let rows: [PointageDay]
    let hours: Double
    let days: Int

    var id: String { empNo }
}

/// Breakdown computed by backend/payroll.py (compute_payslip).
struct PayslipDetails: Codable, Hashable {
    let jours: Int?
    let abs: Int?
    let supHm: String?
    let m25: Double?
    let gross: Double?
    let net: Double?
}

struct Payslip: Codable, Identifiable, Hashable {
    let id: Int
    let employeeName: String
    let matricule: String?
    let periodLabel: String
    let hours: Double
    let hourlyRate: Double
    let currency: String
    let grossTotal: Double
    let advances: Double?
    let netTotal: Double?
    let details: PayslipDetails?

    var netToPay: Double { netTotal ?? grossTotal }
}

struct NewPayslip: Encodable {
    let employeeName: String
    let matricule: String
    let rows: [PointageDay]
    let hourlyRate: Double
    let advances: Double
    let pause: Double
    let m25: Double
    let m50: Double
    let m100: Double
    let companyName: String
    let companyAddress: String
    let companyContact: String
    let currency: String
}

// MARK: Custom stats charts

/// A chart the user added to their Stats page (shared with the website).
struct StatsChart: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let chartType: String
    let source: String
    let groupBy: String
    let metric: String
    let country: String?
    let months: Int?
}

/// What to plot — the body of /stats/query and, with a title and chart
/// type, of POST /stats/charts.
struct StatsChartDraft: Codable, Hashable {
    var title = ""
    var chartType = "bar"
    var source = "clients"
    var groupBy = "visa_status"
    var metric = "count"
    var country: String? = nil
    var months: Int? = nil

    init() {}

    init(_ chart: StatsChart) {
        title = chart.title
        chartType = chart.chartType
        source = chart.source
        groupBy = chart.groupBy
        metric = chart.metric
        country = chart.country
        months = chart.months
    }
}

struct StatsRow: Decodable, Hashable {
    let key: String?
    let value: Double
}

// MARK: Chat

struct ChatMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey { case role, content }
}

struct ChatRequest: Encodable {
    let messages: [ChatMessage]
    let image: String?
}

struct ChatReply: Decodable {
    let reply: String?
}
