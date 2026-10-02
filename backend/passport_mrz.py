"""Passport machine-readable zone (ICAO 9303, TD3: two lines of 44 characters).

OCR turns the zone into text; this module finds the two lines in a pile of OCR
output, repairs the usual OCR slips, and verifies the check digits. A field
that passes its check digit is mathematically right, not just plausible —
that is what lets the app trust it without asking a language model.

Pure functions only (no OCR, no I/O) so it can be unit-tested."""

import re
from dataclasses import dataclass, field
from datetime import date
from typing import Callable

_WEIGHTS = (7, 3, 1)
FILLER = "<"
# OCR reads the "<" filler as these letters.
_FILLER_LOOKALIKES = "KCSELIX"

# Characters OCR confuses with digits / letters in the zones that must be one or the other.
_TO_DIGIT = str.maketrans("OQDILZSBG", "001112568")
_TO_LETTER = str.maketrans("01258", "OIZSB")

# Issuing-state code -> (country, nationality). Anything else falls back to the code itself.
COUNTRIES = {
    "TUN": ("Tunisia", "Tunisian"), "LBY": ("Libya", "Libyan"), "DZA": ("Algeria", "Algerian"),
    "MAR": ("Morocco", "Moroccan"), "EGY": ("Egypt", "Egyptian"), "SDN": ("Sudan", "Sudanese"),
    "MRT": ("Mauritania", "Mauritanian"), "SYR": ("Syria", "Syrian"), "IRQ": ("Iraq", "Iraqi"),
    "JOR": ("Jordan", "Jordanian"), "LBN": ("Lebanon", "Lebanese"), "PSE": ("Palestine", "Palestinian"),
    "SAU": ("Saudi Arabia", "Saudi"), "ARE": ("United Arab Emirates", "Emirati"), "QAT": ("Qatar", "Qatari"),
    "KWT": ("Kuwait", "Kuwaiti"), "OMN": ("Oman", "Omani"), "BHR": ("Bahrain", "Bahraini"),
    "YEM": ("Yemen", "Yemeni"), "TUR": ("Turkey", "Turkish"), "FRA": ("France", "French"),
    "ITA": ("Italy", "Italian"), "D": ("Germany", "German"), "DEU": ("Germany", "German"),
    "ESP": ("Spain", "Spanish"), "PRT": ("Portugal", "Portuguese"), "BEL": ("Belgium", "Belgian"),
    "NLD": ("Netherlands", "Dutch"), "CHE": ("Switzerland", "Swiss"), "AUT": ("Austria", "Austrian"),
    "GBR": ("United Kingdom", "British"), "IRL": ("Ireland", "Irish"), "USA": ("United States", "American"),
    "CAN": ("Canada", "Canadian"), "RUS": ("Russia", "Russian"), "UKR": ("Ukraine", "Ukrainian"),
    "CHN": ("China", "Chinese"), "IND": ("India", "Indian"), "PAK": ("Pakistan", "Pakistani"),
    "BGD": ("Bangladesh", "Bangladeshi"), "MYS": ("Malaysia", "Malaysian"), "IDN": ("Indonesia", "Indonesian"),
    "NGA": ("Nigeria", "Nigerian"), "GHA": ("Ghana", "Ghanaian"), "SEN": ("Senegal", "Senegalese"),
    "CIV": ("Ivory Coast", "Ivorian"), "ETH": ("Ethiopia", "Ethiopian"), "ERI": ("Eritrea", "Eritrean"),
    "SOM": ("Somalia", "Somali"), "TCD": ("Chad", "Chadian"), "NER": ("Niger", "Nigerien"), "MLI": ("Mali", "Malian"),
}


def check_digit(data: str) -> int:
    total = 0
    for i, ch in enumerate(data):
        if ch.isdigit():
            v = int(ch)
        elif ch == FILLER:
            v = 0
        else:
            v = ord(ch) - 55  # A=10 … Z=35
        total += v * _WEIGHTS[i % 3]
    return total % 10


def clean(line: str) -> str:
    """Upper-case, drop spaces, map look-alike punctuation to the filler, keep [A-Z0-9<]."""
    s = line.upper().replace(" ", "").replace("«", FILLER).replace("‹", FILLER)
    return re.sub(r"[^A-Z0-9<]", FILLER, s)


def _date(six: str, *, birth: bool) -> str:
    """YYMMDD -> ISO date, or '' if it isn't a real date."""
    if len(six) != 6 or not six.isdigit():
        return ""
    yy, mm, dd = int(six[:2]), int(six[2:4]), int(six[4:6])
    if birth:
        year = 2000 + yy if yy <= date.today().year % 100 else 1900 + yy
    else:
        year = 2000 + yy  # expiry is always in the 2000s now
    try:
        return date(year, mm, dd).isoformat()
    except ValueError:
        return ""


@dataclass
class Mrz:
    """What the two lines say, plus which check digits passed."""

    issuing_code: str
    nationality_code: str
    passport_number: str
    date_of_birth: str
    sex: str
    date_of_expiry: str
    surname: str
    given_name: str
    checks: dict[str, bool]
    names_certain: bool
    line1: str = ""
    line2: str = ""

    @property
    def checks_ok(self) -> int:
        return sum(self.checks.values())

    @property
    def complete(self) -> bool:
        return all(self.checks.values())


def _split_names(raw: str, known: Callable[[str], bool] | None) -> tuple[str, str, bool]:
    """'CHAKER<<FETHI<SAADEDDINE<<<<<' -> ('CHAKER', 'FETHI SAADEDDINE', True).

    `known(token)` says whether a token also appears in the printed text of the
    page. OCR often reads the "<<" between surname and given names (and the
    trailing filler) as letters like K or C; a token that isn't printed anywhere
    but becomes a printed word once that letter is removed is repaired, and the
    removed letter marks the surname/given-name boundary."""
    tokens = raw.split(FILLER)
    is_known = known or (lambda _t: True)

    def is_junk(t: str) -> bool:
        return t == "" or (re.fullmatch(f"[{_FILLER_LOOKALIKES}]{{1,5}}", t) is not None and not is_known(t))

    while tokens and is_junk(tokens[-1]):
        tokens.pop()
    while tokens and tokens[0] == "":
        tokens.pop(0)

    words: list[tuple[str, bool]] = []  # (word, a boundary follows it)
    boundary_before_next = False
    certain = True
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "":
            # '<<': a gap between two real tokens is the surname / given-name boundary.
            if words and not words[-1][1]:
                words[-1] = (words[-1][0], True)
            i += 1
            continue
        boundary_after = False
        if known is not None and not known(t):
            if len(t) > 3 and known(t[:-1]) and t[-1] in _FILLER_LOOKALIKES:
                t, boundary_after = t[:-1], True
            elif len(t) > 3 and known(t[1:]) and t[0] in _FILLER_LOOKALIKES:
                t = t[1:]
                if words:
                    words[-1] = (words[-1][0], True)
            elif re.fullmatch(f"[{_FILLER_LOOKALIKES}]+", t):
                i += 1  # stray filler garbage in the middle
                continue
            else:
                certain = False
        words.append((t, boundary_after))
        i += 1

    boundary = next((n for n, (_, b) in enumerate(words) if b), None)
    if boundary is None:
        # No visible boundary: the first word is the surname (a guess when there are several).
        certain = certain and len(words) <= 1
        boundary = 0 if words else None
    surname = " ".join(w for w, _ in words[: boundary + 1]) if boundary is not None else ""
    given = " ".join(w for w, _ in words[boundary + 1:]) if boundary is not None else ""
    return surname, given, certain and bool(surname)


_DIGITISH = "0-9OQDILZSBG"
_ANCHOR = re.compile(rf"[A-Z<]{{3}}[{_DIGITISH}]{{6}}[{_DIGITISH}<][MFX<][{_DIGITISH}]{{6}}")


def _align_line2(l2: str) -> str:
    """Line 2 must have the nationality code at position 10. When the photo cuts off
    the first characters (or OCR adds some), every position is shifted and every
    check digit fails: find the nationality + birth date and shift to fit."""
    m = _ANCHOR.search(l2)
    if not m or m.start() == 10 or not 4 <= m.start() <= 14:
        return l2
    shift = 10 - m.start()
    return FILLER * shift + l2 if shift > 0 else l2[-shift:]


def names_part(line1: str, nationality: str) -> tuple[str, str]:
    """(issuing state, the text after it) for an OCR'd line 1. Anchors on the
    nationality code from line 2: line 1 may have lost or gained leading characters."""
    l1 = clean(line1)
    at = l1.find(nationality) if re.fullmatch("[A-Z]{3}", nationality) else -1
    if 0 <= at <= 4:
        return nationality, l1[at + 3:]
    return l1[2:5].translate(_TO_LETTER), l1[5:]


def names_from_printed(raw: str, printed: list[str]) -> tuple[str, str, bool, int] | None:
    """Names from an OCR'd (possibly garbled) line 1, settled against the names
    printed on the page, which OCR reads from clean type.

    The printed text decides where words end (the machine-readable zone shows
    the separators as K, C, S… when OCR can't read "<"), the machine-readable
    zone decides spelling where the two disagree. `printed` is a list of
    letters-only strings, one per printed line. Returns
    (surname, given names, exact, letters matched), `exact` meaning every letter
    agreed with the printed text; None when the page's names can't be found in `raw`."""
    from difflib import SequenceMatcher

    if not raw or not printed:
        return None
    groups = []  # (window start in raw, words, exact, covered, gaps between words)
    for seg in dict.fromkeys(p for p in printed if len(p) >= 3):
        blocks = [b for b in SequenceMatcher(None, seg, raw, autojunk=False).get_matching_blocks() if b.size]
        covered = sum(b.size for b in blocks)
        if not blocks or covered < max(3, round(0.8 * len(seg))):
            continue
        a0, a1 = blocks[0].a, blocks[-1].a + blocks[-1].size
        b0, b1 = blocks[0].b, blocks[-1].b + blocks[-1].size
        if b1 - b0 > (a1 - a0) + 3:   # scattered matches (a label like "SURNAME"): not this name
            continue
        # A disagreeing letter at either edge ("O" printed, "Q" in the zone) isn't a
        # match block but is still part of the name: extend the window across it.
        if a0 and b0 and raw[b0 - 1].isalpha() and raw[b0 - 1] not in _FILLER_LOOKALIKES:
            a0, b0 = a0 - 1, b0 - 1
        if a1 < len(seg) and b1 < len(raw) and raw[b1].isalpha() and raw[b1] not in _FILLER_LOOKALIKES:
            a1, b1 = a1 + 1, b1 + 1
        s_win, r_win = seg[a0:a1], raw[b0:b1]
        out: list[str] = []
        exact = True
        for tag, i1, i2, j1, j2 in SequenceMatcher(None, s_win, r_win, autojunk=False).get_opcodes():
            s_part, r_part = s_win[i1:i2], r_win[j1:j2]
            if tag == "equal":
                out.append(r_part)
            elif tag == "replace":
                exact = False
                same_len = len(s_part) == len(r_part) and FILLER not in r_part
                out.append(r_part if same_len else s_part)
            elif tag == "delete":      # letters the zone lost but the page has
                exact = False
                out.append(s_part)
            else:                      # insert: extra characters in the zone
                if all(c == FILLER or c in _FILLER_LOOKALIKES for c in r_part):
                    out.append(" " * len(r_part))      # a separator
                else:
                    exact = False                      # noise inside a word
        text = "".join(out)
        words = text.split()
        gaps = [len(g) for g in re.findall(r"(?<=\S)\s+(?=\S)", text)]
        if words:
            groups.append((b0, b1, words, exact, covered, gaps))
    if not groups:
        return None
    # Keep the best-covering, non-overlapping groups, in the order they appear.
    groups.sort(key=lambda g: -g[4])
    kept: list = []
    for g in groups:
        if all(min(g[1], k[1]) - max(g[0], k[0]) <= 0.5 * (g[1] - g[0]) for k in kept):
            kept.append(g)
    kept.sort(key=lambda g: g[0])
    exact = all(g[3] for g in kept)
    covered = sum(g[4] for g in kept)
    if len(kept) >= 2:
        surname = " ".join(kept[0][2])
        given = " ".join(w for g in kept[1:] for w in g[2])
    else:
        words, gaps = kept[0][2], kept[0][5]
        cut = next((i + 1 for i, gap in enumerate(gaps) if gap >= 2), 1)
        surname, given = " ".join(words[:cut]), " ".join(words[cut:])
        exact = exact and any(gap >= 2 for gap in gaps)
    return surname, given, exact, covered


def parse(line1: str, line2: str, known: Callable[[str], bool] | None = None) -> Mrz | None:
    """Parse one candidate pair; None if the second line can't be a TD3 line."""
    l2 = _align_line2(clean(line2))
    if len(l2) < 36:
        return None
    l2 = (l2 + FILLER * 44)[:44]

    number, c_num = l2[0:9], l2[9].translate(_TO_DIGIT)
    nationality = l2[10:13].translate(_TO_LETTER)
    dob, c_dob = l2[13:19].translate(_TO_DIGIT), l2[19].translate(_TO_DIGIT)
    sex = l2[20]
    exp, c_exp = l2[21:27].translate(_TO_DIGIT), l2[27].translate(_TO_DIGIT)
    checks = {
        "passport_number": c_num.isdigit() and check_digit(number) == int(c_num),
        "date_of_birth": c_dob.isdigit() and check_digit(dob) == int(c_dob),
        "date_of_expiry": c_exp.isdigit() and check_digit(exp) == int(c_exp),
    }

    l1 = clean(line1)
    issuing, names = names_part(l1, nationality)
    surname, given, certain = _split_names(names, known)

    return Mrz(
        issuing_code=issuing,
        nationality_code=nationality,
        passport_number=number.replace(FILLER, ""),
        date_of_birth=_date(dob, birth=True),
        sex={"M": "M", "F": "F"}.get(sex, "X" if sex == FILLER else ""),
        date_of_expiry=_date(exp, birth=False),
        surname=surname,
        given_name=given,
        checks=checks,
        names_certain=certain,
        line1=l1,
        line2=l2,
    )


def _looks_like_line2(clean_line: str) -> bool:
    # 9-char number, check digit, 3-letter nationality, then 6 digits: allow a few OCR slips.
    s = (clean_line + FILLER * 44)[:44]
    return len(clean_line) >= 36 and sum(c.isdigit() for c in s[13:19]) >= 4 and re.fullmatch("[A-Z0-9<]{3}", s[10:13]) is not None


def _looks_like_line1(clean_line: str) -> bool:
    return len(clean_line) >= 20 and clean_line.count(FILLER) >= 3 and sum(c.isalpha() for c in clean_line) >= 8


def find(lines: list[str], known: Callable[[str], bool] | None = None) -> Mrz | None:
    """Best pair among OCR lines: the one whose check digits pass most.

    Lines may come from several OCR passes (rotations, zoomed strips), so line 1
    and line 2 need not come from the same pass."""
    cleaned = []
    for raw in lines:
        c = clean(raw)
        if len(c) >= 16 and c not in cleaned:
            cleaned.append(c)
    seconds = [c for c in cleaned if _looks_like_line2(c)]
    firsts = [c for c in cleaned if _looks_like_line1(c) and c not in seconds] or [""]
    best: Mrz | None = None
    for l2 in seconds:
        for l1 in firsts:
            m = parse(l1, l2, known)
            if m is None:
                continue
            rank = (m.checks_ok, m.names_certain, bool(m.surname))
            if best is None or rank > (best.checks_ok, best.names_certain, bool(best.surname)):
                best = m
    return best
