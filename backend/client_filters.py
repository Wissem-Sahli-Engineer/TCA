"""Server-side client search, tabs and alert rules, so the website and the
iOS app can page through clients instead of downloading all of them.

The alert rules are the single source of truth here; src/features/clients/
options.js and ios_swift/.../Models.swift show the *reason* text for the
clients the server returns."""

from datetime import date, timedelta

from sqlalchemy import and_, func, or_
from sqlalchemy.sql.elements import ColumnElement

from backend.models import Client
from backend.stats import _client_country

# A flight this many days away (or fewer) with an untreated visa is an alert.
ALERT_TRIP_DAYS = 10
# Visa counts as treated once the passport is ready (or later).
VISA_TREATED = ("passport_ready", "client_notified_passport_ready", "delivered", "closed")
TABS = ("all", "fair", "reservation", "alert")
COUNTRIES = ("tunisia", "libya")


def visa_status():
    """A client without a status is a new file."""
    return func.coalesce(Client.visa_status, "new")


def alert_condition(today: date | None = None) -> ColumnElement:
    """Passport ready but client not told yet, or flight within ALERT_TRIP_DAYS
    while the visa isn't treated."""
    today = today or date.today()
    soon = today + timedelta(days=ALERT_TRIP_DAYS)
    status = visa_status()
    return or_(
        status == "passport_ready",
        and_(
            Client.has_flight.is_(True),
            Client.flight_date.is_not(None),
            Client.flight_date >= today,
            Client.flight_date <= soon,
            status.not_in(VISA_TREATED),
        ),
    )


def like_pattern(term: str) -> str:
    """%term% for ILIKE with ESCAPE '\\' — user text can't act as a wildcard."""
    escaped = term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escaped}%"


def search_conditions(q: str | None) -> list[ColumnElement]:
    """Every word must match the name, passport number, phone or email."""
    conditions = []
    for term in (q or "").split():
        like = like_pattern(term)
        conditions.append(
            or_(
                Client.given_name.ilike(like, escape="\\"),
                Client.surname.ilike(like, escape="\\"),
                Client.passport_number.ilike(like, escape="\\"),
                Client.phone.ilike(like, escape="\\"),
                Client.email.ilike(like, escape="\\"),
            )
        )
    return conditions


def tab_condition(tab: str | None) -> list[ColumnElement]:
    if tab == "fair":
        return [Client.category == "fair"]
    if tab == "reservation":
        return [Client.category == "reservation"]
    if tab == "alert":
        return [alert_condition()]
    return []


def country_condition(country: str | None) -> list[ColumnElement]:
    return [_client_country(country)] if country in COUNTRIES else []
