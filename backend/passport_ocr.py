"""Read a passport photo without a language model.

1. OCR (RapidOCR: free, CPU-only, ~1 s) finds the text on the page.
2. The two machine-readable lines are parsed and verified with their check
   digits (passport_mrz.py) — number, birth date, expiry are then certain.
3. Names are repaired and cross-checked against the printed names.
4. Fields that only exist in the printed section are filled from the page:
   issue date (derived from the expiry and the country's validity period,
   confirmed by the printed date), place of birth and issuing authority.

`read_passport()` returns None when no machine-readable zone can be found, so
the caller can fall back to the slow vision model."""

from __future__ import annotations

import io
import re
import shutil
import statistics
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass
from datetime import date, timedelta
from difflib import SequenceMatcher, get_close_matches

import numpy as np
from PIL import Image, ImageOps

from backend import passport_mrz as mrz

MAX_SIDE = 1600       # longest side sent to OCR
MIN_SIDE = 1300       # small photos are enlarged to this first
ZOOM_WIDTH = 1500     # width of the re-read strip around the machine-readable lines

# How long a passport stays valid, by issuing country (years). Used to derive the issue date.
VALIDITY_YEARS = {"TUN": (5,), "LBY": (8,)}
DEFAULT_VALIDITY = (5, 10, 6, 8)

_engine = None
_engine_lock = threading.Lock()


def warm_up() -> None:
    """Load the OCR models now instead of on the first request."""
    _ocr(Image.new("RGB", (64, 64), "white"))


@dataclass
class Line:
    text: str
    score: float
    x0: float
    y0: float
    x1: float
    y1: float

    @property
    def w(self) -> float:
        return self.x1 - self.x0

    @property
    def h(self) -> float:
        return self.y1 - self.y0

    @property
    def cy(self) -> float:
        return (self.y0 + self.y1) / 2


def _ocr(im: Image.Image) -> list[Line]:
    global _engine
    with _engine_lock:  # one OCR at a time; each takes about a second
        if _engine is None:
            from rapidocr_onnxruntime import RapidOCR

            _engine = RapidOCR()
        result, _ = _engine(np.array(im))
    lines = []
    for box, text, score in result or []:
        xs, ys = [p[0] for p in box], [p[1] for p in box]
        lines.append(Line(str(text), float(score), min(xs), min(ys), max(xs), max(ys)))
    return lines


def _load(data: bytes) -> Image.Image:
    im = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
    longest = max(im.size)
    if longest < MIN_SIDE:
        f = MIN_SIDE / longest
        im = im.resize((round(im.width * f), round(im.height * f)), Image.LANCZOS)
    elif longest > MAX_SIDE:
        im.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    return im


_LINE1_START = re.compile(r"P[A-Z<]?(?:%s)[A-Z<]{12,}" % "|".join(sorted(mrz.COUNTRIES, key=len, reverse=True)))


def _is_mrz_like(text: str) -> bool:
    c = mrz.clean(text)
    # Line 1 with every "<" misread as a letter has no "<" left: recognise it by its start.
    return len(c) >= 16 and (c.count("<") >= 3 or mrz._looks_like_line2(c) or bool(_LINE1_START.match(c)))


def _letters(text: str) -> str:
    return re.sub(r"[^A-Z]", "", text.upper())


def _known_fn(lines: list[Line]):
    """known(token): is this token printed somewhere on the page (outside the MRZ)?"""
    printed = [_letters(l.text) for l in lines if not _is_mrz_like(l.text)]
    printed = [p for p in printed if p]

    def known(token: str) -> bool:
        t = _letters(token)
        return bool(t) and any(t in p for p in printed)

    return known


def _strip_box(im: Image.Image, candidates: list[Line], pad_lines: float) -> tuple[int, int, int, int]:
    """Area around the machine-readable lines. Wide enough for a full 44-character
    line even when only a shorter line (names, padded with "<") was found."""
    h = statistics.median(c.h for c in candidates)
    char_w = max(c.w / max(len(mrz.clean(c.text)), 1) for c in candidates)
    left = min(c.x0 for c in candidates)
    right = max(max(c.x1 for c in candidates), left + char_w * 44)
    x0 = max(0, left - im.width * 0.03)
    x1 = min(im.width, right + im.width * 0.03)
    y0 = max(0, min(c.y0 for c in candidates) - h * pad_lines)
    y1 = min(im.height, max(c.y1 for c in candidates) + h * pad_lines)
    return int(x0), int(y0), int(x1), int(y1)


def _zoom_strip(im: Image.Image, candidates: list[Line]) -> list[Line]:
    """Re-read the area around machine-readable-looking lines, enlarged: finds the
    other line when the first pass missed it and cleans up garbled characters."""
    crop = im.crop(_strip_box(im, candidates, 2.6))
    scale = min(3.0, max(1.0, ZOOM_WIDTH / crop.width))
    if scale > 1.05:
        crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.LANCZOS)
    return _ocr(ImageOps.autocontrast(crop, cutoff=1))


_TESSERACT = shutil.which("tesseract")
_MRZ_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<"


def _tesseract_lines(im: Image.Image) -> list[str]:
    """Second opinion on a small strip. Tesseract reads the "<" filler better than
    RapidOCR does (which turns it into K / C / S); optional: skipped if not installed."""
    if not _TESSERACT:
        return []
    try:
        with tempfile.NamedTemporaryFile(suffix=".png") as f:
            im.save(f.name)
            out = subprocess.run(
                [_TESSERACT, f.name, "-", "--psm", "6", "-c", f"tessedit_char_whitelist={_MRZ_CHARS}"],
                capture_output=True, text=True, timeout=20,
            ).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    return [l for l in out.splitlines() if l.strip()]


def _strip_for_tesseract(im: Image.Image, candidates: list[Line]) -> Image.Image:
    crop = im.crop(_strip_box(im, candidates, 1.2)).convert("L")
    scale = min(4.0, max(1.0, 1800 / crop.width))
    crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.LANCZOS)
    return ImageOps.expand(ImageOps.autocontrast(crop, cutoff=1), border=30, fill=255)


def _tesseract_locate(im: Image.Image) -> list[Line]:
    """Fallback locator for photos RapidOCR can't see the zone in (glare, low
    contrast): Tesseract on the bottom of the page, where the zone always is.
    The text is rough; only the position is used, to zoom in on it."""
    if not _TESSERACT:
        return []
    top = int(im.height * 0.5)
    crop = ImageOps.autocontrast(im.crop((0, top, im.width, im.height)).convert("L"), cutoff=1)
    try:
        with tempfile.NamedTemporaryFile(suffix=".png") as f:
            crop.save(f.name)
            out = subprocess.run(
                [_TESSERACT, f.name, "-", "--psm", "6", "-c", f"tessedit_char_whitelist={_MRZ_CHARS}", "tsv"],
                capture_output=True, text=True, timeout=20,
            ).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    rows: dict[tuple[str, str, str], list[list[str]]] = {}
    for row in out.splitlines()[1:]:
        c = row.split("\t")
        if len(c) == 12 and c[0] == "5" and c[11].strip():
            rows.setdefault((c[2], c[3], c[4]), []).append(c)
    found = []
    for words in rows.values():
        text = " ".join(w[11] for w in words)
        x0, y0 = min(int(w[6]) for w in words), min(int(w[7]) for w in words)
        x1, y1 = max(int(w[6]) + int(w[8]) for w in words), max(int(w[7]) + int(w[9]) for w in words)
        found.append(Line(text, 0.0, x0, y0 + top, x1, y1 + top))
    return [l for l in found if _is_mrz_like(l.text) and l.w > l.h]


def _rotation_order(lines: list[Line]) -> list[int]:
    tall = sum(1 for l in lines if len(l.text) >= 6 and l.h > 1.3 * l.w)
    wide = sum(1 for l in lines if len(l.text) >= 6 and l.w > 1.3 * l.h)
    return [90, 270, 180] if tall > wide else [180, 90, 270]


# ---------------------------------------------------------------------------
# Printed section: issue date, place of birth, issuing authority
# ---------------------------------------------------------------------------

_DATE_RE = re.compile(r"(?<!\d)(\d{2})[\s./-]?(\d{2})[\s./-]?(\d{4})(?!\d)")

# Places that appear on Tunisian / Libyan passports, used to clean up bilingual
# lines where the Arabic part gets read as junk letters ("TUNISIUg").
_PLACES = [
    # Tunisia
    "Tunis", "Ariana", "Ben Arous", "Manouba", "Nabeul", "Zaghouan", "Bizerte", "Beja", "Jendouba", "Le Kef",
    "Siliana", "Sousse", "Monastir", "Mahdia", "Sfax", "Kairouan", "Kasserine", "Sidi Bouzid", "Gabes", "Medenine",
    "Tataouine", "Gafsa", "Tozeur", "Kebili", "Kelibia", "Hammamet", "La Marsa", "Carthage", "La Goulette", "Rades",
    "Megrine", "Menzel Bourguiba", "Manzel Bourguiba", "Manzel Temim", "Menzel Temime", "Djerba", "Zarzis",
    "Houmt Souk", "Mateur", "Testour", "Douz", "Ksar Hellal", "Jemmal", "Msaken", "Ben Guerdane", "El Menzah",
    "El Omrane", "Ettadhamen", "Sfax Medina", "Sfax Sud", "Sfax Ville", "Sfax Nord",
    # Libya
    "Tripoli", "Benghazi", "Misrata", "Misurata", "Tarhuna", "Zawiya", "Zliten", "Khums", "Al Khums", "Sirte", "Sabha",
    "Bayda", "Derna", "Tobruk", "Ajdabiya", "Gharyan", "Zuwara", "Msallatah", "Yefren", "Nalut", "Ghat", "Murzuq",
    "Bani Walid", "Sorman", "Sabratha", "Aziziya",
    # Countries people are born in
    "France", "Italy", "Germany", "Belgium", "Switzerland", "Turkey", "Egypt", "Algeria", "Morocco", "Canada",
    "Spain",
]
_DISPLAY = {p.replace(" ", "").upper(): p for p in _PLACES}
_KNOWN_PLACES = sorted(_DISPLAY, key=len, reverse=True)


def _display_place(compact: str, original: str) -> str:
    return _DISPLAY.get(compact, original.title())


def _clean_place(text: str) -> tuple[str, str]:
    """('value', 'likely' | 'review') — '' when nothing usable."""
    t = text.strip()
    if "/" in t:  # "KELIBIA/قليبية": keep the Latin side
        t = t.split("/")[0]
    t = re.sub(r"[^A-Za-z ]", "", t).strip()
    lead = re.match(r"[A-Z][A-Z ]*", t)
    run = lead.group(0).strip() if lead else ""
    if len(run.replace(" ", "")) < 3:
        return "", ""
    compact = run.replace(" ", "")
    if compact in _KNOWN_PLACES:
        return _display_place(compact, run), "likely"
    # No slash: the Arabic side may have stuck junk letters on the end ("TUNISIUg").
    if "/" not in text:
        for p in _KNOWN_PLACES:
            if compact.startswith(p) and len(compact) - len(p) <= (5 if len(p) >= 6 else 3):
                return _display_place(p, p), "likely"
    if "/" not in text:
        close = get_close_matches(compact, _KNOWN_PLACES, n=1, cutoff=0.82)
        if close:
            return _display_place(close[0], close[0]), "likely"
    return run.title(), "likely" if "/" in text else "review"


def _years_before(d: date, years: int) -> date:
    try:
        return d.replace(year=d.year - years)
    except ValueError:  # 29 February
        return d.replace(year=d.year - years, day=28)


def _printed_dates(lines: list[Line]) -> set[date]:
    found: set[date] = set()
    for l in lines:
        if "<" in l.text:
            continue
        for d, m, y in _DATE_RE.findall(l.text):
            try:
                found.add(date(int(y), int(m), int(d)))
            except ValueError:
                pass
    return found


def _issue_date(m: mrz.Mrz, lines: list[Line]) -> tuple[str, str]:
    """The issue date is not in the machine-readable zone, but expiry = issue date
    + validity - 1 day, so it can be derived, then confirmed against the printed date."""
    if not m.date_of_expiry:
        return "", ""
    expiry = date.fromisoformat(m.date_of_expiry)
    years = VALIDITY_YEARS.get(m.issuing_code, DEFAULT_VALIDITY)
    candidates = [_years_before(expiry + timedelta(days=1), k) for k in dict.fromkeys(years + DEFAULT_VALIDITY)]
    printed = _printed_dates(lines)
    for c in candidates:
        if c in printed:
            return c.isoformat(), "verified"          # derived and printed agree
    # The printed date alone, if it is plausible (a 4-10 year passport ending at the expiry).
    plausible = [d for d in printed if 3.9 * 365 <= (expiry - d).days <= 10.1 * 365]
    if len(plausible) == 1:
        return plausible[0].isoformat(), "review"
    if m.issuing_code in VALIDITY_YEARS:
        return candidates[0].isoformat(), "review"    # derived only
    return "", ""


def _with_neighbours(value: Line, lines: list[Line]) -> str:
    """"MANZEL" and "TEMIM/" are sometimes read as two boxes on one row."""
    row = sorted(
        (b for b in lines if b is not value and abs(b.cy - value.cy) <= 0.6 * value.h and 0 <= b.x0 - value.x1 <= 1.5 * value.h),
        key=lambda b: b.x0,
    )
    return " ".join([value.text] + [b.text for b in row[:2]])


def _value_for(label: Line, lines: list[Line]) -> Line | None:
    """The text printed under (or, failing that, right of) a label."""
    below = [
        b for b in lines
        if b is not label and b.cy > label.cy + 0.3 * label.h and abs(b.x0 - label.x0) <= max(70, label.w * 0.35)
        and b.cy - label.cy <= max(90, label.h * 7)
    ]
    if below:
        return min(below, key=lambda b: b.cy - label.cy)
    right = [b for b in lines if b is not label and abs(b.cy - label.cy) <= label.h * 0.7 and b.x0 >= label.x1 - 5]
    return min(right, key=lambda b: b.x0 - label.x1) if right else None


_DEMONYMS = {re.sub(r"[^A-Z]", "", n.upper()) for _, n in mrz.COUNTRIES.values()} | {"TUNISIAN", "LIBYAN"}


def _compact(text: str) -> str:
    return re.sub(r"[^a-z]", "", text.lower())


def _label_score(text: str, target: str) -> float:
    """How much of `target` ("placeofbirth") appears, in order, in a noisy OCR label."""
    t = _compact(text)
    if len(t) < 3:
        return 0.0
    m = SequenceMatcher(None, target, t, autojunk=False).find_longest_match(0, len(target), 0, len(t))
    ratio = SequenceMatcher(None, target, t[: len(target) + 8], autojunk=False).ratio()
    return max(m.size / len(target), ratio)


def _find_label(lines: list[Line], target: str, rival: str = "", reject: tuple[str, ...] = (), minimum: float = 0.55) -> Line | None:
    """The line that looks most like `target`, and more like it than like `rival`
    ("Date of birth" vs "Place of birth" differ by a few letters OCR may blur)."""
    best, best_score = None, minimum
    for l in lines:
        t = l.text.lower()
        if any(r in t for r in reject) or sum(c.isdigit() for c in t) > len(t) // 2:
            continue
        score = _label_score(l.text, target)
        if rival and _label_score(l.text, rival) >= score:
            continue
        if score > best_score:
            best, best_score = l, score
    return best


def _place_lines(lines: list[Line]) -> list[tuple[Line, str, str]]:
    """Printed lines that read as a known place, in reading order."""
    found = []
    for l in sorted(lines, key=lambda l: (l.cy, l.x0)):
        value, conf = _clean_place(l.text)
        if value and conf == "likely" and _compact(value).upper() in _DISPLAY:
            found.append((l, value, conf))
    return found


def _printed_fields(lines: list[Line], own_names: set[str] = frozenset()) -> dict[str, tuple[str, str]]:
    """place_of_birth and issued_by: read next to their printed labels, or, when
    the labels are unreadable, picked from the places printed on the page."""
    out: dict[str, tuple[str, str]] = {}
    pob_label = _find_label(lines, "placeofbirth", rival="dateofbirth", minimum=0.5)
    iss_label = _find_label(lines, "issuingauthority", reject=("code", "state", "stale"), minimum=0.4) or \
        _find_label(lines, "issuingplace", reject=("code", "state", "stale"), minimum=0.4)
    for key, label in (("place_of_birth", pob_label), ("issued_by", iss_label)):
        value = _value_for(label, lines) if label else None
        if value:
            cleaned, conf = _clean_place(_with_neighbours(value, lines))
            compact = _compact(cleaned).upper()
            if cleaned and compact not in _DEMONYMS and compact not in own_names:
                out[key] = (cleaned, conf)
    places = _place_lines(lines)
    if len(out) < 2 and places:
        # Reading order on both templates: place of birth first, issuing place last.
        if "place_of_birth" not in out:
            out["place_of_birth"] = (places[0][1], "review")
        if "issued_by" not in out and len(places) >= 2:
            out["issued_by"] = (places[-1][1], "review")
    return out


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def _names_consensus(texts: list[str], nationality: str, printed: list[str], fallback: mrz.Mrz):
    """Surname / given names from every reading of line 1, settled against the printed names.
    Returns (surname, given, confidence)."""
    results = []
    for text in texts:
        c = mrz.clean(text)
        if not mrz._looks_like_line1(c):
            continue
        _, names = mrz.names_part(c, nationality)
        r = mrz.names_from_printed(names, printed)
        if r:
            results.append(r)
    if results:
        pairs = [(r[0], r[1]) for r in results]
        agreed = [p for p in set(pairs) if pairs.count(p) >= 2]
        exact = [r for r in results if r[2]]
        if exact:
            best = max(exact, key=lambda r: r[3])
            return best[0], best[1], "verified"
        if agreed:
            best = max(agreed, key=lambda p: pairs.count(p))
            return best[0], best[1], "likely"
        best = max(results, key=lambda r: r[3])
        return best[0], best[1], "review"
    return fallback.surname, fallback.given_name, "likely" if fallback.names_certain else "review"


def read_passport(data: bytes) -> dict | None:
    t0 = time.perf_counter()
    base = _load(data)
    texts: list[str] = []
    passes: list[tuple[int, Image.Image, list[Line]]] = []
    best: tuple[mrz.Mrz, int] | None = None
    order = [0]
    done: set[int] = set()

    def rank(m: mrz.Mrz):
        return (m.checks_ok, bool(m.surname), m.names_certain)

    while order:
        angle = order.pop(0)
        if angle in done:
            continue
        done.add(angle)
        im = base if angle == 0 else base.rotate(angle, expand=True)
        lines = _ocr(im)
        passes.append((angle, im, lines))
        texts += [l.text for l in lines]
        known = _known_fn(lines)

        found = mrz.find(texts, known)
        candidates = [l for l in lines if _is_mrz_like(l.text) and l.w > l.h]
        if not candidates and sum(1 for l in lines if l.w > l.h) > len(lines) / 2:
            candidates = _tesseract_locate(im)   # upright page, zone not seen: look again at the bottom
        if candidates and not (found and found.complete and found.names_certain):
            # Re-read the zone enlarged, with a second engine: finds a missed line,
            # and reads the "<" filler that RapidOCR turns into letters.
            texts += [l.text for l in _zoom_strip(im, candidates)]
            texts += _tesseract_lines(_strip_for_tesseract(im, candidates))
            found = mrz.find(texts, known) or found
        if found and (best is None or rank(found) > rank(best[0])):
            best = (found, len(passes) - 1)
        # Good enough to stop: the numbers check out (or all but one, e.g. the photo cuts
        # off the first character of the passport number) and the names are there. More
        # rotations would only cost time; uncertain fields are flagged for the user anyway.
        if best and best[0].checks_ok >= 2 and best[0].surname:
            break
        if angle == 0:
            order += _rotation_order(lines)

    if best is None or best[0].checks_ok < 2:
        return None

    m, at = best
    # The printed section is read from the orientation that produced the most upright text
    # (the zone may have been found in a zoomed re-read of a different pass).
    page_lines = max(
        (p[2] for p in passes),
        key=lambda ls: sum(len(l.text) for l in ls if l.w > l.h and not _is_mrz_like(l.text)),
    )
    printed = [p for p in (_letters(l.text) for l in page_lines if not _is_mrz_like(l.text)) if p]
    surname, given, names_conf = _names_consensus(texts, m.nationality_code, printed, m)

    conf: dict[str, str] = {}
    issuing = m.issuing_code if m.issuing_code in mrz.COUNTRIES else m.nationality_code
    country, _ = mrz.COUNTRIES.get(issuing, (issuing, issuing))
    _, nationality = mrz.COUNTRIES.get(m.nationality_code, (m.nationality_code, m.nationality_code))
    fields = {
        "country": country,
        "passport_number": m.passport_number,
        "type": "P",
        "nationality": nationality,
        "given_name": given.title(),
        "surname": surname.title(),
        "date_of_birth": m.date_of_birth,
        "sex": m.sex,
        "place_of_birth": "",
        "date_of_issue": "",
        "date_of_expiry": m.date_of_expiry,
        "issued_by": "",
    }
    conf["passport_number"] = "verified" if m.checks["passport_number"] else "review"
    conf["date_of_birth"] = "verified" if m.checks["date_of_birth"] and m.date_of_birth else "review"
    conf["date_of_expiry"] = "verified" if m.checks["date_of_expiry"] and m.date_of_expiry else "review"
    for f in ("country", "type", "nationality", "sex"):
        conf[f] = "likely" if fields[f] else "review"
    conf["surname"] = names_conf if surname else "review"
    conf["given_name"] = names_conf if given else "review"

    issue, issue_conf = _issue_date(m, page_lines)
    if issue:
        fields["date_of_issue"], conf["date_of_issue"] = issue, issue_conf
    own = {re.sub(r"[^A-Z]", "", w.upper()) for w in (surname + " " + given).split()}
    for key, (value, c) in _printed_fields(page_lines, own).items():
        fields[key], conf[key] = value, c

    return {
        "fields": fields,
        "confidence": conf,
        "engine": "mrz",
        "ms": round((time.perf_counter() - t0) * 1000),
        "passes": len(passes),
        "checks": f"{m.checks_ok}/3",
    }
