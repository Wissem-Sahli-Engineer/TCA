import glob
import json
import os
import shutil
import subprocess
from pathlib import Path

from backend.db import ROOT_DIR

TEMPLATES_DIR = Path(__file__).resolve().parent / "invoice_templates"
WORK_DIR = ROOT_DIR / "uploads" / "invoices"


def _tex_bin_dir() -> str | None:
    matches = glob.glob(os.path.expanduser("~/Library/TinyTeX/bin/*"))
    return matches[0] if matches else None


def _tex_env() -> dict:
    env = os.environ.copy()
    bin_dir = _tex_bin_dir()
    if bin_dir:
        env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
    return env


def _latex_escape(value) -> str:
    if value is None:
        return ""
    s = str(value)
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    for char, repl in replacements.items():
        s = s.replace(char, repl)
    return s


def _run(cmd: list[str], cwd: Path):
    result = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, timeout=90, env=_tex_env()
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{cmd[0]} failed (exit {result.returncode}):\n"
            + result.stdout[-4000:] + "\n" + result.stderr[-2000:]
        )


def _render_facture(invoice, work_dir: Path) -> str:
    template = (TEMPLATES_DIR / "facture.tex").read_text(encoding="utf-8")

    items = json.loads(invoice.items_json or "[]")
    article_lines = "\n".join(
        r"\article{%s}{%s}{%s}"
        % (_latex_escape(i["designation"]), i["quantity"], i["unit_price"])
        for i in items
    ) or r"\article{}{0}{0}"

    replacements = {
        "%%INV_NUM%%": _latex_escape(invoice.number),
        "%%INV_DATE%%": _latex_escape(invoice.issue_date.isoformat()),
        "%%CLIENT_NAME%%": _latex_escape(invoice.client_name),
        "%%CLIENT_MF%%": _latex_escape(invoice.client_mf or ""),
        "%%COMPANY_NAME%%": _latex_escape(invoice.company_name or ""),
        "%%TVA_RATE%%": str(invoice.tva_rate),
        "%%TIMBRE%%": str(invoice.timbre),
        "%%MONTANT_REGLE%%": str(invoice.amount_paid),
        "%%ARTICLES%%": article_lines,
    }
    for token, value in replacements.items():
        template = template.replace(token, value)

    (work_dir / "facture.tex").write_text(template, encoding="utf-8")
    return "facture.tex"


def _render_recu(invoice, work_dir: Path) -> str:
    template = (TEMPLATES_DIR / "recu.tex").read_text(encoding="utf-8")

    total_due = invoice.amount_paid + max(0.0, invoice.timbre)  # placeholder if no items
    items = json.loads(invoice.items_json or "[]")
    if items:
        total_due = sum(i["quantity"] * i["unit_price"] for i in items)
    amount_left = max(0.0, total_due - invoice.amount_paid)
    status = "تم الدفع بالكامل" if amount_left <= 0 else "دفعة جزئية"

    replacements = {
        "%%RECEIPT_NO%%": _latex_escape(invoice.number),
        "%%RECEIPT_DATE%%": invoice.issue_date.isoformat(),
        "%%CLIENT_NAME%%": _latex_escape(invoice.client_name),
        "%%CLIENT_PASSPORT%%": _latex_escape(invoice.client_passport or "-"),
        "%%SERVICE_TYPE%%": _latex_escape(invoice.service_type or "-"),
        "%%AMOUNT_DUE%%": f"{total_due:.3f}",
        "%%AMOUNT_PAID%%": f"{invoice.amount_paid:.3f}",
        "%%AMOUNT_LEFT%%": f"{amount_left:.3f}",
        "%%STATUS_TEXT%%": status,
    }
    for token, value in replacements.items():
        template = template.replace(token, value)

    (work_dir / "recu.tex").write_text(template, encoding="utf-8")
    return "recu.tex"


def generate_invoice_pdf(invoice) -> Path:
    """Render the facture/recu LaTeX template for this invoice and compile it to PDF.
    Returns the path to the produced PDF.
    """
    work_dir = WORK_DIR / invoice.number
    work_dir.mkdir(parents=True, exist_ok=True)

    for asset in (
        "logo.png",
        "signature.png",
        "Amiri-Regular.ttf",
        "Amiri-Bold.ttf",
        "Amiri-Italic.ttf",
        "Amiri-BoldItalic.ttf",
    ):
        src = TEMPLATES_DIR / asset
        if src.is_file():
            shutil.copy(src, work_dir / asset)

    if invoice.doc_type == "recu":
        tex_name = _render_recu(invoice, work_dir)
        _run(["xelatex", "-interaction=nonstopmode", "-halt-on-error", tex_name], cwd=work_dir)
    else:
        tex_name = _render_facture(invoice, work_dir)
        # facture.tex is kept byte-for-byte as authored; a tikz `align` +
        # `\textsuperscript` regression in this TeX Live release otherwise
        # crashes the compile. Patched here at the compiler-invocation level
        # (not in the .tex source) by wrapping \textsuperscript in \mbox
        # right before the document body runs.
        patch = (
            r"\AtBeginDocument{\let\oldtextsuperscript\textsuperscript"
            r"\renewcommand{\textsuperscript}[1]{\mbox{\oldtextsuperscript{#1}}}}"
            r"\input{%s}" % tex_name
        )
        _run(["pdflatex", "-interaction=nonstopmode", "-halt-on-error", patch], cwd=work_dir)

    pdf_path = work_dir / tex_name.replace(".tex", ".pdf")
    if not pdf_path.is_file():
        raise RuntimeError("PDF was not produced")
    return pdf_path
