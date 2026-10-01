from datetime import date, datetime, timezone

from pydantic import ValidationInfo, field_validator, model_validator
from sqlmodel import Field, SQLModel

# Allowed values for the client pick-lists. The labels (English/Arabic) live
# in src/i18n/translations.js under visa.*, visaType.*, paymentMethod.*,
# category.* and payment.*; the web and iOS apps show the same lists.
VISA_STATUSES = (
    "new",
    "document_review",
    "missing_documents",
    "ready_for_invitation",
    "accepted_in_system",
    "invitation_issued",
    "client_notified",
    "awaiting_passport",
    "passport_received",
    "file_submitted",
    "awaiting_result",
    "passport_ready",
    "client_notified_passport_ready",
    "delivered",
    "closed",
)
VISA_TYPES = (
    "pre_entry_swift",
    "government_invitation",
    "first_entry_connect",
    "companion_s1_s2",
    "study_x1_x2",
    "visa_z",
    "other",  # free text goes in visa_type_other
)
PAYMENT_METHODS = ("cash", "card", "transfer", "cheque")
PAYMENT_STATES = ("unpaid", "partial", "paid")
CLIENT_CATEGORIES = ("normal", "fair", "reservation")
CURRENCIES = ("USD", "EUR", "TND", "LYD")


class ClientBase(SQLModel):
    given_name: str = Field(max_length=100)
    surname: str = Field(max_length=100)
    passport_number: str = Field(max_length=30, unique=True, index=True)
    country: str | None = Field(default=None, max_length=100)
    nationality: str | None = Field(default=None, max_length=100)
    type: str | None = Field(default=None, max_length=10)
    sex: str | None = Field(default=None, max_length=10)
    date_of_birth: date | None = None
    place_of_birth: str | None = Field(default=None, max_length=100)
    date_of_issue: date | None = None
    date_of_expiry: date | None = None
    issued_by: str | None = Field(default=None, max_length=100)

    # Contact & business info
    phone: str | None = Field(default=None, max_length=30)
    email: str | None = Field(default=None, max_length=150)
    entreprise_name: str | None = Field(default=None, max_length=150)
    code_fiscal: str | None = Field(default=None, max_length=50)

    # Classification: which tab the client is listed under
    category: str = Field(default="normal", max_length=20)
    fair_email: str | None = Field(default=None, max_length=150)  # fair clients only

    # Visa
    visa_status: str | None = Field(default=None, max_length=50)
    visa_type: str | None = Field(default=None, max_length=50)
    visa_type_other: str | None = Field(default=None, max_length=150)  # when visa_type == "other"

    # Travel (any client)
    has_flight: bool = False
    flight_date: date | None = None  # only with has_flight
    destination: str | None = Field(default=None, max_length=150)

    # Reservation details (reservation clients only)
    airline_name: str | None = Field(default=None, max_length=150)
    hotel_reservation: bool = False
    hotel_name: str | None = Field(default=None, max_length=150)  # only with hotel_reservation
    duration: str | None = Field(default=None, max_length=50)
    reservation_amount: float | None = None

    # Billing
    prix_dossier: float | None = None
    paiement_type: str | None = Field(default=None, max_length=50)
    payment_state: str | None = Field(default=None, max_length=20)
    currency: str | None = Field(default=None, max_length=10)


class Client(ClientBase, table=True):
    __tablename__ = "clients"

    id: int | None = Field(default=None, primary_key=True)
    photo_path: str | None = Field(default=None, max_length=255)
    # Name of the signed-in user who added the client — set by the server.
    created_by: str | None = Field(default=None, max_length=150)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ClientCreate(ClientBase):
    """Body of POST /clients, as sent by the Add client page."""

    user_photo: str | None = None  # data:image/...;base64,... manually uploaded client photo

    @field_validator("*", mode="before")
    @classmethod
    def blank_to_none(cls, v, info: ValidationInfo):
        if isinstance(v, str):
            v = v.strip() or None
        if v is None and info.field_name == "category":
            return "normal"
        if v is None and info.field_name in ("has_flight", "hotel_reservation"):
            return False
        return v

    @field_validator("currency", mode="before")
    @classmethod
    def normalize_currency(cls, v):
        return v.strip().upper() if isinstance(v, str) and v.strip() else v

    @field_validator("visa_status", "visa_type", "paiement_type", "payment_state", "category", "currency")
    @classmethod
    def check_choice(cls, v, info: ValidationInfo):
        allowed = {
            "visa_status": VISA_STATUSES,
            "visa_type": VISA_TYPES,
            "paiement_type": PAYMENT_METHODS,
            "payment_state": PAYMENT_STATES,
            "category": CLIENT_CATEGORIES,
            "currency": CURRENCIES,
        }[info.field_name]
        if v is not None and v not in allowed:
            raise ValueError(f"{info.field_name} must be one of: {', '.join(allowed)}")
        return v

    @model_validator(mode="after")
    def drop_irrelevant_fields(self):
        if self.category != "fair":
            self.fair_email = None
        if self.visa_type != "other":
            self.visa_type_other = None
        if not self.has_flight:
            self.flight_date = None
            self.airline_name = None
        if self.category != "reservation":
            self.airline_name = None
            self.hotel_reservation = False
            self.duration = None
            self.reservation_amount = None
        if not self.hotel_reservation:
            self.hotel_name = None
        return self

    @field_validator("passport_number")
    @classmethod
    def normalize_passport(cls, v):
        return v.upper() if v else v


class ClientFile(SQLModel, table=True):
    __tablename__ = "client_files"

    id: int | None = Field(default=None, primary_key=True)
    client_id: int = Field(foreign_key="clients.id", index=True)
    filename: str = Field(max_length=255)
    path: str = Field(max_length=255)
    content_type: str | None = Field(default=None, max_length=100)
    uploaded_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class TreasuryEntryBase(SQLModel):
    country: str = Field(max_length=20, index=True)
    kind: str = Field(max_length=10)  # "spending" | "gathering"
    product_name: str = Field(max_length=150)
    price: float
    entry_date: date
    recorded_by: str | None = Field(default=None, max_length=100)  # who wrote the entry
    counterparty: str | None = Field(default=None, max_length=150)  # who they dealt with


class TreasuryEntry(TreasuryEntryBase, table=True):
    __tablename__ = "treasury_entries"

    id: int | None = Field(default=None, primary_key=True)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class TreasuryEntryCreate(TreasuryEntryBase):
    pass


class BankAccount(SQLModel, table=True):
    __tablename__ = "bank_accounts"

    id: int | None = Field(default=None, primary_key=True)
    country: str = Field(max_length=20, index=True)
    name: str = Field(max_length=150)
    currency: str = Field(max_length=10)
    balance: float = 0


class BankTransactionBase(SQLModel):
    account_id: int = Field(foreign_key="bank_accounts.id", index=True)
    label: str = Field(max_length=150)
    amount: float  # positive = deposit, negative = withdrawal
    entry_date: date


class BankTransaction(BankTransactionBase, table=True):
    __tablename__ = "bank_transactions"

    id: int | None = Field(default=None, primary_key=True)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class BankTransactionCreate(BankTransactionBase):
    pass


class InvoiceItem(SQLModel):
    designation: str
    quantity: float
    unit_price: float


class InvoiceBase(SQLModel):
    country: str = Field(max_length=20, index=True)
    doc_type: str = Field(max_length=10)  # "facture" | "recu"
    client_id: int | None = Field(default=None, foreign_key="clients.id")
    client_name: str = Field(max_length=150)
    client_passport: str | None = Field(default=None, max_length=30)
    client_mf: str | None = Field(default=None, max_length=50)  # matricule fiscal
    company_name: str | None = Field(default=None, max_length=150)
    service_type: str | None = Field(default=None, max_length=100)  # recu only
    issue_date: date
    tva_rate: float = 0.19
    timbre: float = 1
    amount_paid: float = 0
    items_json: str = "[]"  # JSON-encoded list[InvoiceItem]; facture only


class Invoice(InvoiceBase, table=True):
    __tablename__ = "invoices"

    id: int | None = Field(default=None, primary_key=True)
    number: str = Field(max_length=30, unique=True, index=True)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class InvoiceCreate(InvoiceBase):
    items: list[InvoiceItem] = []


class AgencyRequestBase(SQLModel):
    name: str = Field(max_length=150)
    description: str
    submitted_date: date
    status: str = Field(default="pending", max_length=20)  # pending | approved | rejected


class AgencyRequest(AgencyRequestBase, table=True):
    __tablename__ = "agency_requests"

    id: int | None = Field(default=None, primary_key=True)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class AgencyRequestCreate(AgencyRequestBase):
    pass


class EmployeeRequestBase(SQLModel):
    category: str = Field(max_length=30)  # vacations | salary-advances | loans
    employee_name: str = Field(max_length=150)
    detail: str
    submitted_date: date
    status: str = Field(default="pending", max_length=20)


class EmployeeRequest(EmployeeRequestBase, table=True):
    __tablename__ = "employee_requests"

    id: int | None = Field(default=None, primary_key=True)
    # Whoever submitted it — set from the authenticated session, never trusted
    # from the client. Non-admins only ever see their own rows; this is what
    # makes the request private between that agent and the admin.
    user_email: str = Field(default="", max_length=200, index=True)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class EmployeeRequestCreate(EmployeeRequestBase):
    pass


class PayslipBase(SQLModel):
    employee_name: str = Field(max_length=150)
    period_label: str = Field(max_length=50)  # e.g. "September 2026"
    hours: float
    hourly_rate: float
    currency: str = Field(default="TND", max_length=10)


class Payslip(PayslipBase, table=True):
    __tablename__ = "payslips"

    id: int | None = Field(default=None, primary_key=True)
    matricule: str | None = Field(default=None, max_length=50)
    gross_total: float
    advances: float = Field(default=0)
    net_total: float | None = None
    # Full computed breakdown (summary lines, daily detail, parameters) so the
    # PDF can be re-rendered exactly; null for payslips made before the
    # ZKTeco import existed.
    details_json: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class PayslipCreate(SQLModel):
    """Body of POST /payroll/payslips. With `rows` (from /payroll/parse-pointage)
    the payslip is computed like paie_app.html; without them it falls back to
    the old hours × rate request still sent by the iOS app."""

    employee_name: str = Field(max_length=150)
    hourly_rate: float
    currency: str = Field(default="TND", max_length=10)
    matricule: str | None = None
    rows: list[dict] | None = None
    advances: float = 0
    pause: float = 60
    m25: float = 25
    m50: float = 50
    m100: float = 100
    company_name: str | None = None
    company_address: str | None = None
    company_contact: str | None = None
    period_label: str | None = None
    hours: float | None = None


class User(SQLModel, table=True):
    __tablename__ = "users"

    id: int | None = Field(default=None, primary_key=True)
    name: str = Field(max_length=150)
    email: str = Field(max_length=200, unique=True, index=True)
    password_hash: str = Field(max_length=200)
    role: str = Field(default="Agent", max_length=20)  # "Admin" | "Agent"
    status: str = Field(default="pending", max_length=20)  # "pending" | "active" | "rejected"
    confirmation_token: str | None = Field(default=None, max_length=100, index=True)
    confirmation_expires: datetime | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
