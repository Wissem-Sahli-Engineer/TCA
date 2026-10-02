"""Custom charts on the Stats page: one dataset, grouped by one field,
counted or summed — computed here so the web and iOS apps show the same
numbers. The labels for every key below live in src/i18n/translations.js
under customCharts.*."""

from datetime import date, datetime, time, timezone

from fastapi import HTTPException
from sqlalchemy import DateTime, func, or_
from sqlmodel import Session, select

from backend.models import (
    BankAccount,
    Client,
    EmployeeRequest,
    Invoice,
    Payslip,
    StatsQuery,
    TreasuryEntry,
    User,
)

CHART_TYPES = ("bar", "hbar", "line", "pie")
PERIODS = (3, 6, 12, 24)
# Grouping by one of these sorts chronologically instead of by value.
TIME_DIMS = ("month", "flight_month")
MAX_GROUPS = 25

# Client countries are free text from the passport; these spellings count
# as the agency's two countries when filtering clients.
COUNTRY_ALIASES = {
    "tunisia": ("tunisia", "tunisie", "tunisian", "tunisien", "tunisienne", "tun", "tn", "تونس", "تونسي", "تونسية"),
    "libya": ("libya", "libye", "libyan", "libyen", "libyenne", "lby", "ly", "ليبيا", "ليبي", "ليبية"),
}


def _month(column):
    return func.to_char(column, "YYYY-MM")


def _client_country(country):
    aliases = COUNTRY_ALIASES[country]
    return or_(
        func.lower(func.trim(Client.country)).in_(aliases),
        func.lower(func.trim(Client.nationality)).in_(aliases),
    )


# admin: only admins may chart it (the same data is admin-only elsewhere).
# own: for non-admins, restrict to their own rows.
# date: column the "last N months" filter applies to (see _since()).
SOURCES = {
    "clients": {
        "model": Client,
        "admin": False,
        "date": Client.created_at,
        "country": _client_country,
        "dims": {
            "visa_status": func.coalesce(Client.visa_status, "new"),
            "visa_type": Client.visa_type,
            "category": Client.category,
            "payment_state": Client.payment_state,
            "paiement_type": Client.paiement_type,
            "currency": Client.currency,
            "nationality": Client.nationality,
            "country": Client.country,
            "sex": Client.sex,
            "destination": Client.destination,
            "created_by": Client.created_by,
            "month": _month(Client.created_at),
            "flight_month": _month(Client.flight_date),
        },
        "metrics": {
            "prix_dossier": Client.prix_dossier,
            "reservation_amount": Client.reservation_amount,
        },
    },
    "invoices": {
        "model": Invoice,
        "admin": True,
        "date": Invoice.issue_date,
        "country": lambda c: Invoice.country == c,
        "dims": {
            "doc_type": Invoice.doc_type,
            "country": Invoice.country,
            "month": _month(Invoice.issue_date),
            "client_name": Invoice.client_name,
            "company_name": Invoice.company_name,
            "service_type": Invoice.service_type,
        },
        "metrics": {"amount_paid": Invoice.amount_paid},
    },
    "treasury": {
        "model": TreasuryEntry,
        "admin": True,
        "date": TreasuryEntry.entry_date,
        "country": lambda c: TreasuryEntry.country == c,
        "dims": {
            "kind": TreasuryEntry.kind,
            "country": TreasuryEntry.country,
            "month": _month(TreasuryEntry.entry_date),
            "product_name": TreasuryEntry.product_name,
            "recorded_by": TreasuryEntry.recorded_by,
            "counterparty": TreasuryEntry.counterparty,
        },
        "metrics": {"price": TreasuryEntry.price},
    },
    "bank_accounts": {
        "model": BankAccount,
        "admin": True,
        "date": None,
        "country": lambda c: BankAccount.country == c,
        "dims": {
            "name": BankAccount.name,
            "country": BankAccount.country,
            "currency": BankAccount.currency,
        },
        "metrics": {"balance": BankAccount.balance},
    },
    "payslips": {
        "model": Payslip,
        "admin": True,
        "date": Payslip.created_at,
        "country": None,
        "dims": {
            "employee_name": Payslip.employee_name,
            "period_label": Payslip.period_label,
            "month": _month(Payslip.created_at),
        },
        "metrics": {
            "net_total": func.coalesce(Payslip.net_total, Payslip.gross_total),
            "gross_total": Payslip.gross_total,
            "hours": Payslip.hours,
            "advances": Payslip.advances,
        },
    },
    "employee_requests": {
        "model": EmployeeRequest,
        "admin": False,
        "own": lambda user: EmployeeRequest.user_email == user.email,
        "date": EmployeeRequest.submitted_date,
        "country": None,
        "dims": {
            "category": EmployeeRequest.category,
            "status": EmployeeRequest.status,
            "employee_name": EmployeeRequest.employee_name,
            "month": _month(EmployeeRequest.submitted_date),
        },
        "metrics": {},
    },
}


def normalize_query(q: StatsQuery, user: User) -> None:
    """Validate a chart definition in place (422/403 on anything unknown)."""
    source = SOURCES.get(q.source)
    if not source:
        raise HTTPException(status_code=422, detail=f"Unknown data source: {q.source}")
    if source["admin"] and user.role != "Admin":
        raise HTTPException(status_code=403, detail="Admin access required for this data")
    if q.group_by not in source["dims"]:
        raise HTTPException(status_code=422, detail=f"Can't group {q.source} by {q.group_by}")
    if q.metric != "count" and q.metric not in source["metrics"]:
        raise HTTPException(status_code=422, detail=f"Can't sum {q.metric} for {q.source}")
    if q.country in ("", "all") or source["country"] is None:
        q.country = None
    if q.country is not None and q.country not in COUNTRY_ALIASES:
        raise HTTPException(status_code=422, detail="country must be tunisia, libya or empty")
    if source["date"] is None:
        q.months = None
    if q.months is not None and q.months not in PERIODS:
        raise HTTPException(status_code=422, detail=f"months must be one of {PERIODS}")


def _first_day_months_ago(months: int) -> date:
    """First day of the month `months - 1` months back, so "last 3 months"
    covers this month and the two before it."""
    today = date.today()
    year, month = today.year, today.month - (months - 1)
    while month <= 0:
        month += 12
        year -= 1
    return date(year, month, 1)


def _since(column, months: int):
    start = _first_day_months_ago(months)
    # Timestamp columns (created_at) need an aware datetime; DATE columns a date.
    if isinstance(getattr(column.type, "impl_instance", column.type), DateTime):
        return column >= datetime.combine(start, time.min, tzinfo=timezone.utc)
    return column >= start


def run_query(session: Session, user: User, q: StatsQuery) -> list[dict]:
    normalize_query(q, user)
    source = SOURCES[q.source]
    dim = source["dims"][q.group_by]
    value = func.count() if q.metric == "count" else func.coalesce(func.sum(source["metrics"][q.metric]), 0)

    stmt = select(dim.label("key"), value.label("value")).select_from(source["model"])
    if q.country:
        stmt = stmt.where(source["country"](q.country))
    if q.months:
        stmt = stmt.where(_since(source["date"], q.months))
    if "own" in source and user.role != "Admin":
        stmt = stmt.where(source["own"](user))
    stmt = stmt.group_by(dim)
    if q.group_by in TIME_DIMS:
        stmt = stmt.order_by(dim.asc().nulls_last())
    else:
        stmt = stmt.order_by(value.desc()).limit(MAX_GROUPS)

    return [
        {"key": key if key not in ("", None) else None, "value": round(float(val or 0), 3)}
        for key, val in session.exec(stmt).all()
    ]
