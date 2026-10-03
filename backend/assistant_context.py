"""What the chat assistant knows about the business.

Every question gets a fresh, compact snapshot of the live database appended to the
system prompt, so "how much is in the bank?" or "what is Ben Ali's visa status?" is
answered from real figures instead of guesses. The snapshot is built per user:
money, invoices and payroll are admin-only (like the pages and endpoints), and an
agent only sees their own employee requests."""

import re
from datetime import date

from sqlalchemy import func
from sqlmodel import Session, select

from backend.client_filters import COUNTRIES, alert_condition, country_condition, search_conditions, visa_status
from backend.models import (
    BankAccount,
    BankTransaction,
    Client,
    EmployeeRequest,
    Invoice,
    Payslip,
    TreasuryEntry,
    User,
    AgencyRequest,
)

MAX_MATCHED_CLIENTS = 5
CURRENCY = {"tunisia": "TND", "libya": "LYD"}


def _money(value: float | None, currency: str = "") -> str:
    return f"{value or 0:,.2f} {currency}".strip()


def _client_line(c: Client) -> str:
    parts = [
        f"{c.given_name} {c.surname}",
        f"passport {c.passport_number}",
        f"visa status: {c.visa_status or 'new'}",
    ]
    if c.visa_type:
        parts.append(f"visa type: {c.visa_type_other if c.visa_type == 'other' and c.visa_type_other else c.visa_type}")
    parts.append(f"category: {c.category}")
    if c.country:
        parts.append(f"passport country: {c.country}")
    if c.phone:
        parts.append(f"phone {c.phone}")
    if c.has_flight and c.flight_date:
        parts.append(f"flight {c.flight_date} to {c.destination or '?'}")
    if c.prix_dossier is not None:
        parts.append(
            f"file price {_money(c.prix_dossier, c.currency or '')}, payment: {c.payment_state or 'unpaid'}"
            + (f" by {c.paiement_type}" if c.paiement_type else "")
        )
    if c.date_of_expiry:
        parts.append(f"passport expires {c.date_of_expiry}")
    return "- " + "; ".join(parts)


def _matched_clients(session: Session, question: str) -> list[Client]:
    """Clients the question talks about: every word of 3+ letters is tried against
    the names, passport numbers, phones and emails; the best-covered clients win."""
    words = [w for w in re.findall(r"[\w'-]{3,}", question) if not w.isdigit() or len(w) >= 5]
    if not words:
        return []
    scores: dict[int, tuple[int, Client]] = {}
    for word in words[:12]:
        for client in session.exec(select(Client).where(*search_conditions(word)).limit(20)).all():
            hits, _ = scores.get(client.id, (0, client))
            scores[client.id] = (hits + 1, client)
    # A single common word matching many people is noise: keep only clients matched by
    # the most words, and drop the lot if it's still too ambiguous.
    if not scores:
        return []
    best = max(h for h, _ in scores.values())
    top = [c for h, c in scores.values() if h == best]
    return top[:MAX_MATCHED_CLIENTS] if len(top) <= 20 else []


def _clients_section(session: Session, question: str) -> list[str]:
    total = session.exec(select(func.count()).select_from(Client)).one()
    status = visa_status()
    by_status = session.exec(select(status, func.count()).group_by(status)).all()
    lines = [
        "## Clients",
        f"Total clients: {total}.",
        "By visa status: " + (", ".join(f"{s}: {n}" for s, n in by_status) or "none") + ".",
        "By country: "
        + ", ".join(
            f"{c}: {session.exec(select(func.count()).select_from(Client).where(*country_condition(c))).one()}"
            for c in COUNTRIES
        )
        + ".",
    ]
    alerts = session.exec(select(Client).where(alert_condition()).limit(10)).all()
    if alerts:
        lines.append("Clients in alert (passport ready to announce, or flight within 10 days with visa not treated):")
        lines += [_client_line(c) for c in alerts]
    matched = _matched_clients(session, question)
    if matched:
        lines.append("Clients matching the question:")
        lines += [_client_line(c) for c in matched]
    return lines


def _finance_section(session: Session) -> list[str]:
    today = date.today()
    month_start = today.replace(day=1)
    lines = ["## Money (admin only)"]
    for country, currency in CURRENCY.items():
        accounts = session.exec(select(BankAccount).where(BankAccount.country == country)).all()
        entries = session.exec(
            select(TreasuryEntry).where(TreasuryEntry.country == country, TreasuryEntry.entry_date >= month_start)
        ).all()
        gathering = sum(e.price for e in entries if e.kind == "gathering")
        spending = sum(e.price for e in entries if e.kind == "spending")
        lines.append(f"{country.title()} ({currency}):")
        if accounts:
            lines.append(
                "  Bank accounts: "
                + "; ".join(f"{a.name}: {_money(a.balance, a.currency)}" for a in accounts)
                + f". Total: {_money(sum(a.balance for a in accounts), currency)}."
            )
        else:
            lines.append("  No bank accounts.")
        lines.append(
            f"  This month's treasury: gathered {_money(gathering, currency)}, spent {_money(spending, currency)}, "
            f"net {_money(gathering - spending, currency)}."
        )
        recent = session.exec(
            select(TreasuryEntry).where(TreasuryEntry.country == country).order_by(TreasuryEntry.entry_date.desc(), TreasuryEntry.id.desc()).limit(5)
        ).all()
        if recent:
            lines.append("  Latest treasury entries: " + "; ".join(f"{e.entry_date} {e.kind} {e.product_name} {_money(e.price)}" for e in recent))
        invoices = session.exec(select(func.count()).select_from(Invoice).where(Invoice.country == country)).one()
        lines.append(f"  Invoices and receipts issued: {invoices}.")
    txs = session.exec(select(BankTransaction).order_by(BankTransaction.entry_date.desc(), BankTransaction.id.desc()).limit(5)).all()
    if txs:
        lines.append("Latest bank transactions: " + "; ".join(f"{t.entry_date} {t.label} {_money(t.amount)}" for t in txs))
    slips = session.exec(select(Payslip).order_by(Payslip.id.desc()).limit(5)).all()
    if slips:
        lines.append(
            "Latest payslips: "
            + "; ".join(f"{p.employee_name} {p.period_label} net {_money(p.net_total if p.net_total is not None else p.gross_total, p.currency)}" for p in slips)
        )
    return lines


def _requests_section(session: Session, user: User) -> list[str]:
    query = select(EmployeeRequest).order_by(EmployeeRequest.id.desc()).limit(15)
    if user.role != "Admin":
        query = query.where(EmployeeRequest.user_email == user.email)
    rows = session.exec(query).all()
    lines = ["## Employee requests" + ("" if user.role == "Admin" else " (this user's own)")]
    if not rows:
        return lines + ["None."]
    lines += [f"- #{r.id} {r.category} by {r.employee_name} on {r.submitted_date}: {r.detail} — {r.status}" for r in rows]
    if user.role == "Admin":
        agency = session.exec(select(AgencyRequest).order_by(AgencyRequest.id.desc()).limit(10)).all()
        if agency:
            lines.append("Agency requests: " + "; ".join(f"#{a.id} {a.name} ({a.status})" for a in agency))
    return lines


def build_context(session: Session, user: User, question: str) -> str:
    sections = [
        f"Today is {date.today().isoformat()}. You are talking to {user.name} (role: {user.role}).",
        *_clients_section(session, question),
    ]
    if user.role == "Admin":
        sections += _finance_section(session)
    else:
        sections.append("## Money\nFinancial data (bank, treasury, invoices, payroll) is restricted to admins; do not discuss it.")
    sections += _requests_section(session, user)
    return "\n".join(sections)
