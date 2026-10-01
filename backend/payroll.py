"""Fiche de paie, ported from paie_app.html: reads a ZKTeco K40 time-clock
export, computes the payslip with the same rules, and renders the Arabic
« بطاقة خلاص الأجر » as a PDF (XeLaTeX + the Amiri font already bundled for
the receipts)."""

import io
import json
import math
import re
import shutil
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

import openpyxl
import xlrd

from backend.db import ROOT_DIR
from backend.invoices import TEMPLATES_DIR, _latex_escape, _run

TEMPLATE_PATH = Path(__file__).resolve().parent / "payroll_template.tex"
WORK_DIR = ROOT_DIR / "uploads" / "payslips"

MONTHS_AR = {
    1: "جانفي", 2: "فيفري", 3: "مارس", 4: "أفريل", 5: "ماي", 6: "جوان",
    7: "جويلية", 8: "أوت", 9: "سبتمبر", 10: "أكتوبر", 11: "نوفمبر", 12: "ديسمبر",
}

DEFAULT_COMPANY = {
    "company_name": "شركة تونس للإستشارات والمساعدة",
    "company_address": "عدد 85 شارع فلسطين عمارة القدس الطابق الثاني مكتب رقم 3 تونس، 1010",
    "company_contact": "info@tunis-consulting.com — +216 29 190 039 | +216 28 846 888",
}

DEFAULT_OPTIONS = {"pause": 60, "m25": 25, "m50": 50, "m100": 100}


# ---------------------------------------------------------------------------
# Reading the time-clock export
# ---------------------------------------------------------------------------

def _hhmm(minutes: int) -> str:
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def cell_str(v) -> str:
    """Same normalisation as cellStr() in paie_app.html: time-of-day cells
    become "HH:MM", everything else a trimmed string."""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "True" if v else "False"
    if isinstance(v, datetime):
        # Time-only cells come back anchored on Excel's 1899/1900 epoch.
        if v.year <= 1900:
            return _hhmm(v.hour * 60 + v.minute)
        return v.strftime("%d/%m/%Y")
    if isinstance(v, date):
        return v.strftime("%d/%m/%Y")
    if isinstance(v, time):
        return _hhmm(v.hour * 60 + v.minute)
    if isinstance(v, timedelta):
        return _hhmm(round(v.total_seconds() / 60))
    if isinstance(v, (int, float)):
        if 0 < v < 1:
            return _hhmm(round(v * 1440))
        return str(int(v)) if float(v).is_integer() else str(v)
    return str(v).strip()


def _xlrd_cell(cell, datemode):
    if cell.ctype == xlrd.XL_CELL_DATE:
        if cell.value < 1:
            return time(*divmod(round(cell.value * 1440), 60))
        return xlrd.xldate_as_datetime(cell.value, datemode)
    if cell.ctype == xlrd.XL_CELL_BOOLEAN:
        return bool(cell.value)
    if cell.ctype in (xlrd.XL_CELL_EMPTY, xlrd.XL_CELL_BLANK):
        return None
    return cell.value


def _read_sheet(raw: bytes) -> list[list]:
    # .xlsx is a zip ("PK"); anything else is legacy .xls — the ZKTeco
    # software writes raw BIFF streams that only xlrd understands.
    if raw[:2] == b"PK":
        wb = openpyxl.load_workbook(io.BytesIO(raw), data_only=True)
        return [list(r) for r in wb.worksheets[0].iter_rows(values_only=True)]
    book = xlrd.open_workbook(file_contents=raw, logfile=io.StringIO())
    sheet = book.sheet_by_index(0)
    return [[_xlrd_cell(c, book.datemode) for c in sheet.row(r)] for r in range(sheet.nrows)]


def parse_pointage(raw: bytes) -> list[dict]:
    """Group the export's daily rows by employee (one file may hold several)."""
    aoa = _read_sheet(raw)
    if not aoa:
        return []
    head = [cell_str(h).lower() for h in aoa[0]]

    def col(name):
        return next((i for i, h in enumerate(head) if h.startswith(name)), -1)

    ci = {
        "emp": col("emp no"), "mat": col("matricule"), "prenom": col("prénom"), "nom": col("nom"),
        "date": col("date"), "hor": col("horaire"), "deb": col("début"), "fin": col("fin"),
        "ent": col("entrée"), "sor": col("sortie"), "hsup": col("h sup"), "absent": col("absent"),
        "reel": col("présence réelle"), "plan": col("présence planning"),
        "we": col("weekend"), "hol": col("holiday"),
    }

    employees: dict[str, dict] = {}
    for row in aoa[1:]:
        if not row:
            continue

        def g(key):
            i = ci[key]
            return cell_str(row[i]) if 0 <= i < len(row) else ""

        if not g("date"):
            continue
        emp_no = g("emp") or "1"
        if emp_no not in employees:
            name = " ".join(p for p in (g("prenom"), g("nom")) if p)
            employees[emp_no] = {
                "emp_no": emp_no,
                "employee_name": name or "—",
                "matricule": g("mat") or emp_no,
                "rows": [],
            }
        is_true = lambda key: g(key).lower() == "true"  # noqa: E731
        employees[emp_no]["rows"].append({
            "date": g("date"), "hor": g("hor"), "deb": g("deb"), "fin": g("fin"),
            "ent": g("ent"), "sor": g("sor"), "hsup": g("hsup"),
            "reel": g("reel"), "plan": g("plan"),
            "absent": is_true("absent"), "we": is_true("we"), "hol": is_true("hol"),
        })

    result = []
    for emp in employees.values():
        # Legacy clients (iOS app) still read employee_name + hours.
        totals = compute_payslip(emp["rows"], {**DEFAULT_OPTIONS, "rate": 0, "advances": 0})
        emp["hours"] = round(totals["worked_minutes"] / 60, 2)
        emp["days"] = len(emp["rows"])
        result.append(emp)
    return result


# ---------------------------------------------------------------------------
# Calculation — a line-for-line port of compute() in paie_app.html
# ---------------------------------------------------------------------------

_TIME_RE = re.compile(r"(\d{1,2}):(\d{2})")


def to_min(s) -> int | None:
    m = _TIME_RE.search(cell_str(s))
    return int(m.group(1)) * 60 + int(m.group(2)) if m else None


def hm(minutes) -> str:
    minutes = max(0, math.floor(minutes + 0.5))
    return f"{minutes // 60}h{minutes % 60:02d}"


def _num(value, default):
    try:
        return float(value)
    except (TypeError, ValueError):
        return float(default)


def compute_payslip(rows: list[dict], opts: dict) -> dict:
    pause = _num(opts.get("pause"), 60)
    rate = _num(opts.get("rate"), 0)
    adv = _num(opts.get("advances"), 0)
    m25, m50, m100 = (_num(opts.get(k), DEFAULT_OPTIONS[k]) for k in ("m25", "m50", "m100"))
    k25, k50, k100 = 1 + m25 / 100, 1 + m50 / 100, 1 + m100 / 100

    today = date.today()
    base = sup = we = fe = 0
    jours = absences = 0
    month, year = today.month, today.year
    detail = []

    for d in rows:
        dm = re.search(r"(\d{2})/(\d{2})/(\d{4})", d.get("date", ""))
        if dm:
            month, year = int(dm.group(2)), int(dm.group(3))
        E, S = to_min(d.get("ent")), to_min(d.get("sor"))
        D = to_min(d.get("deb"))
        D = 480 if D is None else D
        F = to_min(d.get("fin"))
        F = 990 if F is None else F
        plan, reel = to_min(d.get("plan")), to_min(d.get("reel"))
        is_we = bool(d.get("we")) or bool(re.search("weekend", d.get("hor", ""), re.I))
        no_punch = E is None and S is None and reel is None

        if d.get("absent") or no_punch:
            kind, label = "abs", "غياب"
        elif d.get("hol"):
            kind, label = "fe", "عطلة رسمية"
        elif is_we:
            kind, label = "we", "عطلة أسبوعية"
        else:
            kind, label = "nm", "يوم عادي"

        e_or_d = D if E is None else E
        s_or_f = F if S is None else S
        if kind == "we":
            planning = plan if plan is not None else max(min(s_or_f, F) - max(e_or_d, D), 0)
            reelle = reel if reel is not None else max(s_or_f - e_or_d, 0)
        elif kind == "abs":
            planning = reelle = 0
        else:
            planning = plan if plan is not None else max(F - max(e_or_d, D), 0) - pause
            planning = max(planning, 0)
            ot = S - F if S is not None and S > F else 0
            reelle = reel if reel is not None else planning + ot

        if kind == "abs":
            absences += 1
        elif kind == "we":
            we += reelle
            jours += 1
        elif kind == "fe":
            fe += reelle
            jours += 1
        else:
            base += planning
            sup += max(reelle - planning, 0)
            jours += 1

        detail.append({
            "date": d.get("date", ""), "ent": d.get("ent") or "—", "sor": d.get("sor") or "—",
            "tot": "—" if kind == "abs" else hm(reelle), "label": label, "kind": kind,
        })

    m_base = base / 60 * rate
    m_sup = sup / 60 * rate * k25
    m_we = we / 60 * rate * k50
    m_fe = fe / 60 * rate * k100
    gross = m_base + m_sup + m_we + m_fe
    net = gross - adv

    def pct(x):
        return f"{x:g}"

    return {
        "month": month, "year": year, "jours": jours, "abs": absences, "rate": rate,
        "advances": adv, "pause": pause, "m25": m25, "m50": m50, "m100": m100,
        "worked_minutes": base + sup + we + fe, "sup_hm": hm(sup),
        "lines": [
            {"label": "الأجر الأساسي", "hours": hm(base), "amount": round(m_base, 3)},
            {"label": f"ساعات إضافية {pct(m25)}%+", "hours": hm(sup), "amount": round(m_sup, 3)},
            {"label": f"عمل السبت / الأحد {pct(m50)}%+", "hours": hm(we), "amount": round(m_we, 3)},
            {"label": f"عطلة رسمية {pct(m100)}%+", "hours": hm(fe), "amount": round(m_fe, 3)},
            {"label": "التسبقات", "hours": "—", "amount": round(-adv, 3) + 0.0},
        ],
        "gross": round(gross, 3), "net": round(net, 3), "detail": detail,
    }


def legacy_details(hours: float, rate: float) -> dict:
    """Payslips from before the ZKTeco import (or from clients that only send
    hours × rate) have no daily detail — render them as a single base line."""
    amount = round(hours * rate, 3)
    return {
        "month": None, "year": None, "jours": None, "abs": None, "rate": rate,
        "advances": 0.0, "sup_hm": "0h00",
        "lines": [{"label": "الأجر الأساسي", "hours": hm(hours * 60), "amount": amount}],
        "gross": amount, "net": amount, "detail": [],
    }


# ---------------------------------------------------------------------------
# PDF
# ---------------------------------------------------------------------------

def _money(x) -> str:
    return f"{(x or 0) + 0.0:.3f} د.ت"


def _local_time(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone().strftime("%d/%m/%Y %H:%M")


def _ar(text) -> str:
    return r"\ar{" + _latex_escape(text) + "}"


def generate_payslip_pdf(payslip) -> Path:
    details = json.loads(payslip.details_json) if payslip.details_json else legacy_details(
        payslip.hours, payslip.hourly_rate
    )
    company = {**DEFAULT_COMPANY, **(details.get("company") or {})}

    if details.get("month"):
        period = _ar(f"{MONTHS_AR[details['month']]} {details['year']}")
        year = details["year"]
    else:
        # Older payslips carry a free-text (usually Latin) label, which must
        # stay outside \ar{} or its words come out reversed.
        period = _latex_escape(payslip.period_label)
        year = payslip.created_at.year

    def opt(v):
        return "—" if v is None else str(v)

    # Tables are typeset left-to-right with their columns already reversed,
    # so they read right-to-left like the HTML sheet without relying on
    # bidi's tabular reversal.
    summary_rows = "\n".join(
        rf"{_ar(_money(l['amount']))} & {l['hours']} & {_ar(l['label'])} \\ \arrayrulecolor{{line}}\hline"
        for l in details["lines"]
    )
    daily_rows = []
    for d in details["detail"]:
        cells = ["", _ar(d["label"]), *(_latex_escape(d[k]) for k in ("tot", "sor", "ent", "date"))]
        prefix = ""
        if d["kind"] == "abs":
            cells = [r"\textcolor{danger}{" + c + "}" for c in cells]
        elif d["kind"] in ("we", "fe"):
            prefix = r"\rowcolor{weekend}"
        daily_rows.append(prefix + " & ".join(cells) + r" \\ \hline")

    replacements = {
        "%%GENERATED_AT%%": _local_time(payslip.created_at),
        "%%META_YEAR%%": str(year),
        "%%COMPANY_NAME%%": _latex_escape(company["company_name"]),
        "%%COMPANY_ADDRESS%%": _latex_escape(company["company_address"]),
        "%%COMPANY_CONTACT%%": _latex_escape(company["company_contact"]),
        "%%EMPLOYEE_NAME%%": _latex_escape(payslip.employee_name),
        "%%MATRICULE%%": _latex_escape(payslip.matricule or "—"),
        "%%PERIOD%%": period,
        "%%RATE%%": _latex_escape(_money(details["rate"])),
        "%%JOURS%%": opt(details.get("jours")),
        "%%ABSENCES%%": opt(details.get("abs")),
        "%%SUMMARY_ROWS%%": summary_rows,
        "%%NET%%": _latex_escape(_money(details["net"])),
        "%%DAILY_ROWS%%": "\n".join(daily_rows),
        "%%HAS_DAILY%%": "true" if details["detail"] else "false",
    }
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    for token, value in replacements.items():
        template = template.replace(token, value)

    work_dir = WORK_DIR / f"PAY-{payslip.id:05d}"
    work_dir.mkdir(parents=True, exist_ok=True)
    for asset in ("logo.png", "Amiri-Regular.ttf", "Amiri-Bold.ttf", "Amiri-Italic.ttf", "Amiri-BoldItalic.ttf"):
        src = TEMPLATES_DIR / asset
        if src.is_file():
            shutil.copy(src, work_dir / asset)
    (work_dir / "payslip.tex").write_text(template, encoding="utf-8")

    _run(["xelatex", "-interaction=nonstopmode", "-halt-on-error", "payslip.tex"], cwd=work_dir)

    pdf_path = work_dir / "payslip.pdf"
    if not pdf_path.is_file():
        raise RuntimeError("PDF was not produced")
    return pdf_path
