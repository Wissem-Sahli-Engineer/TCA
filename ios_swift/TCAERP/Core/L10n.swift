import Foundation

/// Looks up UI strings in translations.json — a copy of the web app's
/// src/i18n/translations.js, so both apps share the same English/Arabic text.
/// Keys use the same dotted paths as the web (`t("clients.addClient")`).
enum L10n {
    static var language = "en"

    private static let table: [String: Any] = {
        guard
            let url = Bundle.main.url(forResource: "translations", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }()

    /// Strings only the native app needs (tab names, settings, pickers).
    private static let extra: [String: [String: String]] = [
        "en": [
            "nav.accounting": "Accounting",
            "nav.requests": "Requests",
            "nav.more": "More",
            "nav.settings": "Settings",
            "settings.language": "Language",
            "settings.appearance": "Appearance",
            "settings.system": "System",
            "settings.light": "Light",
            "settings.dark": "Dark",
            "settings.server": "Server",
            "settings.serverAddress": "Server address",
            "settings.serverHint": "The address of the TCA backend, e.g. http://192.168.1.10:8001",
            "settings.account": "Account",
            "settings.testConnection": "Test connection",
            "settings.connectionOk": "Server reachable",
            "settings.connectionFailed": "Could not reach the server",
            "media.takePhoto": "Take photo",
            "media.photoLibrary": "Photo library",
            "media.files": "Browse files",
            "media.choose": "Choose…",
            "clients.addDocuments": "Add documents",
            "clients.uploaded": "Files uploaded",
            "clients.uploadFailed": "Could not upload files",
            "clients.allStatuses": "All statuses",
            "common.retry": "Retry",
            "common.done": "Done",
            "common.new": "New",
            "invoicesTab.newDocument": "New document",
            "treasuryTab.newEntry": "New entry",
            "bankingTab.newAccount": "New account",
            "bankingTab.newTransaction": "New transaction",
            "requests.newRequest": "New request",
            "payroll.chooseFile": "Choose Excel file",
            "chat.clear": "Clear conversation",
            "chat.attachScreen": "Attach the screen you were on",
            "search.hint": "Type at least 2 characters",
            "banking.deposit": "Deposit",
            "banking.withdrawal": "Withdrawal",
            "payroll.hoursUnit": "h",
            "clients.requiredFields": "Given name, surname and passport number are required",
        ],
        "ar": [
            "nav.accounting": "المحاسبة",
            "nav.requests": "الطلبات",
            "nav.more": "المزيد",
            "nav.settings": "الإعدادات",
            "settings.language": "اللغة",
            "settings.appearance": "المظهر",
            "settings.system": "النظام",
            "settings.light": "فاتح",
            "settings.dark": "داكن",
            "settings.server": "الخادم",
            "settings.serverAddress": "عنوان الخادم",
            "settings.serverHint": "عنوان خادم TCA، مثل http://192.168.1.10:8001",
            "settings.account": "الحساب",
            "settings.testConnection": "اختبار الاتصال",
            "settings.connectionOk": "الخادم متاح",
            "settings.connectionFailed": "تعذّر الوصول إلى الخادم",
            "media.takePhoto": "التقاط صورة",
            "media.photoLibrary": "مكتبة الصور",
            "media.files": "تصفح الملفات",
            "media.choose": "اختر…",
            "clients.addDocuments": "إضافة مستندات",
            "clients.uploaded": "تم رفع الملفات",
            "clients.uploadFailed": "تعذّر رفع الملفات",
            "clients.allStatuses": "كل الحالات",
            "common.retry": "إعادة المحاولة",
            "common.done": "تم",
            "common.new": "جديد",
            "invoicesTab.newDocument": "مستند جديد",
            "treasuryTab.newEntry": "قيد جديد",
            "bankingTab.newAccount": "حساب جديد",
            "bankingTab.newTransaction": "معاملة جديدة",
            "requests.newRequest": "طلب جديد",
            "payroll.chooseFile": "اختر ملف Excel",
            "chat.clear": "مسح المحادثة",
            "chat.attachScreen": "إرفاق الشاشة التي كنت عليها",
            "search.hint": "اكتب حرفين على الأقل",
            "banking.deposit": "إيداع",
            "banking.withdrawal": "سحب",
            "payroll.hoursUnit": "س",
            "clients.requiredFields": "الاسم واللقب ورقم الجواز مطلوبة",
        ],
    ]

    static func t(_ key: String, lang: String? = nil) -> String {
        let lang = lang ?? language
        return lookup(lang, key) ?? lookup("en", key) ?? key
    }

    private static func lookup(_ lang: String, _ key: String) -> String? {
        if let value = extra[lang]?[key] { return value }
        var node: Any? = table[lang]
        for part in key.split(separator: ".") {
            node = (node as? [String: Any])?[String(part)]
            if node == nil { return nil }
        }
        return node as? String
    }
}

/// Shorthand used throughout the views, mirroring the web's `t(...)`.
func tr(_ key: String) -> String { L10n.t(key) }
