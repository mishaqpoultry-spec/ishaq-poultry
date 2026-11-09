"""PDF generation (A4, white, green headings). Shared header/footer with
"Page X of N" on every page; long tables split across pages and repeat their
header row automatically (repeatRows=1)."""

from decimal import Decimal
from functools import lru_cache
from io import BytesIO
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas as rl_canvas
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from svglib.svglib import svg2rlg

from app.core.config import get_settings
from app.models import Delivery

GREEN_DARK = colors.HexColor("#1B6B3A")
GREEN_SOFT = colors.HexColor("#EAF5EC")
GREY = colors.HexColor("#D9DEE3")
TEXT = colors.HexColor("#1F2933")
MUTED = colors.HexColor("#6B7280")
RED = colors.HexColor("#C62828")
PAID = colors.HexColor("#2E7D32")

MARGIN = 15 * mm
CONTENT_W = A4[0] - 2 * MARGIN
HEADER_H = 30 * mm
LOGO = Path(__file__).resolve().parent.parent / "assets" / "logo.svg"

S = {
    "body": ParagraphStyle("body", fontName="Helvetica", fontSize=9.5, leading=13, textColor=TEXT),
    "muted": ParagraphStyle("muted", fontName="Helvetica", fontSize=8.5, leading=11, textColor=MUTED),
    "h1": ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=17, leading=21, textColor=GREEN_DARK, alignment=1),
    "section": ParagraphStyle("section", fontName="Helvetica-Bold", fontSize=11, leading=14, textColor=GREEN_DARK),
    "cell": ParagraphStyle("cell", fontName="Helvetica", fontSize=9, leading=11.5, textColor=TEXT),
    "cellb": ParagraphStyle("cellb", fontName="Helvetica-Bold", fontSize=9, leading=11.5, textColor=TEXT),
    "th": ParagraphStyle("th", fontName="Helvetica-Bold", fontSize=8.8, leading=11, textColor=colors.white),
    "right": ParagraphStyle("right", fontName="Helvetica", fontSize=9, leading=11.5, textColor=TEXT, alignment=TA_RIGHT),
}


def rs(v: Decimal | None) -> str:
    v = Decimal(v or 0)
    s = f"{abs(v):,.2f}"
    return f"Rs. -{s}" if v < 0 else f"Rs. {s}"


def kgs(v: Decimal | None) -> str:
    return f"{Decimal(v or 0):,.3f} KG"


@lru_cache
def _logo_drawing():
    try:
        d = svg2rlg(str(LOGO))
        scale = (18 * mm) / d.width
        d.width, d.height = d.width * scale, d.height * scale
        d.scale(scale, scale)
        return d
    except Exception:  # logo is decorative; never fail a PDF because of it
        return None


class _NumberedCanvas(rl_canvas.Canvas):
    """Two-pass canvas so each page can print 'Page X of N'."""

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self._saved = []

    def showPage(self):
        self._saved.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        total = len(self._saved)
        for state in self._saved:
            self.__dict__.update(state)
            w, _ = A4
            self.setFont("Helvetica", 8)
            self.setFillColor(MUTED)
            self.drawRightString(w - MARGIN, 9 * mm, f"Page {self._pageNumber} of {total}")
            super().showPage()
        super().save()


def _header_footer(title: str, right_lines: list[str]):
    s = get_settings()

    def draw(c: rl_canvas.Canvas, doc):
        w, h = A4
        top = h - MARGIN
        logo = _logo_drawing()
        x = MARGIN
        if logo is not None:
            logo.drawOn(c, MARGIN, top - 18 * mm)
            x = MARGIN + 21 * mm
        c.setFillColor(TEXT)
        c.setFont("Helvetica-Bold", 19)
        c.drawString(x, top - 8 * mm, s.company_name.upper())
        c.setFont("Helvetica", 9)
        c.setFillColor(MUTED)
        c.drawString(x, top - 13 * mm, "Chicken Supply & Distribution")
        contact = " | ".join(p for p in [s.company_address, s.company_phone, f"WhatsApp: {s.company_phone}"] if p)
        c.drawString(x, top - 17.5 * mm, contact)
        c.setFillColor(TEXT)
        c.setFont("Helvetica-Bold", 10.5)
        c.drawRightString(w - MARGIN, top - 6 * mm, title)
        c.setFont("Helvetica", 8.5)
        c.setFillColor(MUTED)
        for i, line in enumerate(right_lines):
            c.drawRightString(w - MARGIN, top - (11 + i * 4.2) * mm, line)
        c.setStrokeColor(GREEN_DARK)
        c.setLineWidth(1.2)
        c.line(MARGIN, top - 22 * mm, w - MARGIN, top - 22 * mm)
        # footer
        c.setLineWidth(0.8)
        c.line(MARGIN, 13 * mm, w - MARGIN, 13 * mm)
        c.setFont("Helvetica", 8)
        c.setFillColor(MUTED)
        c.drawString(MARGIN, 9 * mm, f"{s.company_name} · {s.company_phone} · Computer generated document")

    return draw


def _doc(buf: BytesIO, title: str) -> SimpleDocTemplate:
    return SimpleDocTemplate(
        buf,
        pagesize=A4,
        leftMargin=MARGIN,
        rightMargin=MARGIN,
        topMargin=MARGIN + HEADER_H,
        bottomMargin=20 * mm,
        title=title,
        author=get_settings().company_name,
    )


def section_bar(text: str) -> Table:
    t = Table([[Paragraph(text, S["section"])]], colWidths=[CONTENT_W])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), GREEN_SOFT),
                ("BOX", (0, 0), (-1, -1), 0.5, GREY),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return t


def data_table(header: list[str], rows: list[list], col_widths, right_cols=(), total_row=False) -> Table:
    """Green header row (repeats on every page), grey grid, optional bold total row."""
    data = [[Paragraph(h, S["th"]) for h in header]]
    for r in rows:
        data.append([c if not isinstance(c, str) else Paragraph(c, S["cell"]) for c in r])
    t = Table(data, colWidths=col_widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), GREEN_DARK),
        ("GRID", (0, 0), (-1, -1), 0.5, GREY),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    for c in right_cols:
        style.append(("ALIGN", (c, 1), (c, -1), "RIGHT"))
    if total_row:
        style += [("BACKGROUND", (0, -1), (-1, -1), GREEN_SOFT), ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold")]
    t.setStyle(TableStyle(style))
    return t


def signature_block(left="Prepared by", right="Authorized Signature") -> Table:
    t = Table(
        [[Paragraph(f"{left}: ________________", S["body"]), Paragraph(f"{right}: ________________", S["body"])]],
        colWidths=[CONTENT_W / 2, CONTENT_W / 2],
    )
    t.setStyle(TableStyle([("TOPPADDING", (0, 0), (-1, -1), 28), ("LEFTPADDING", (0, 0), (-1, -1), 0)]))
    return t


# --- Invoice ---------------------------------------------------------------


def _n(v: Decimal) -> str:
    """12,345 or 12,345.50 — drop .00 for a cleaner message."""
    v = Decimal(v or 0)
    s = f"{abs(v):,.2f}"
    if s.endswith(".00"):
        s = s[:-3]
    return f"-{s}" if v < 0 else s


def _invoice_figures(d: Delivery) -> dict:
    after = d.total_amount  # amount - discount (+ charges, normally 0)
    return {
        "after": after,
        "total_payable": d.previous_balance + after,
        "remaining": d.balance_after,
    }


def invoice_pdf(d: Delivery) -> bytes:
    buf = BytesIO()
    when = d.delivery_date.strftime("%d %b %Y") + (f", {d.delivery_time.strftime('%I:%M %p')}" if d.delivery_time else "")
    doc = _doc(buf, f"Invoice {d.invoice_no}")
    cu = d.customer
    f = _invoice_figures(d)
    story = [Paragraph("INVOICE", S["h1"]), Spacer(1, 4 * mm)]

    info = [
        ["Customer", cu.name, "Invoice No.", d.invoice_no],
        ["Contact", cu.phone or "-", "Date / Time", when],
    ]
    t = Table(
        [[Paragraph(f"<b>{a}</b>", S["cell"]), Paragraph(b, S["cell"]), Paragraph(f"<b>{c}</b>", S["cell"]), Paragraph(e, S["cell"])] for a, b, c, e in info],
        colWidths=[26 * mm, 62 * mm, 30 * mm, 62 * mm],
    )
    t.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.5, GREY), ("BACKGROUND", (0, 0), (0, -1), GREEN_SOFT), ("BACKGROUND", (2, 0), (2, -1), GREEN_SOFT), ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    story += [t, Spacer(1, 6 * mm), section_bar("Supply Details"), Spacer(1, 2 * mm)]

    unit = "/KG" if d.rate_unit.value == "per_kg" else "/piece"
    story.append(
        data_table(
            ["Item", "Pieces", "Total Weight", "Rate", "Supply Amount"],
            [[
                f"{d.chicken_type.value.title()} Chicken",
                str(d.birds) if d.birds else "—",
                f"{d.net_weight:,.3f} KG",
                f"Rs. {d.rate:,.2f}{unit}",
                rs(d.amount),
            ]],
            [50 * mm, 22 * mm, 36 * mm, 34 * mm, 38 * mm],
            right_cols=(1, 2, 3, 4),
        )
    )
    story += [Spacer(1, 6 * mm), section_bar("Bill Summary"), Spacer(1, 2 * mm)]

    rows = [("Supply amount", rs(d.amount), None, False)]
    if d.discount:
        rows.append((f"Discount (Rs. {d.discount_per_kg:,.2f} per KG x {d.net_weight:,.3f} KG)", f"- {rs(d.discount)}", RED, False))
    if d.additional_charges:
        rows.append(("Additional charges", rs(d.additional_charges), None, False))
    rows += [
        ("Amount after discount", rs(f["after"]), None, True),
        ("Previous balance (old udhaar)", rs(d.previous_balance), RED if d.previous_balance > 0 else None, False),
        ("Total payable", rs(f["total_payable"]), None, True),
        ("Payment received", f"- {rs(d.payment_received)}", PAID, False),
        ("Remaining balance", rs(f["remaining"]), RED if f["remaining"] > 0 else PAID, True),
    ]
    data = [[Paragraph("Description", S["th"]), Paragraph("Amount (PKR)", S["th"])]]
    style = [("BACKGROUND", (0, 0), (-1, 0), GREEN_DARK), ("GRID", (0, 0), (-1, -1), 0.5, GREY), ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]
    for label, value, color, bold in rows:
        b = ("<b>", "</b>") if bold else ("", "")
        vs = ParagraphStyle("v", parent=S["right"], textColor=color or TEXT)
        data.append([Paragraph(f"{b[0]}{label}{b[1]}", S["cell"]), Paragraph(f"{b[0]}{value}{b[1]}", vs)])
    style.append(("BACKGROUND", (0, len(rows)), (-1, len(rows)), GREEN_SOFT))
    t = Table(data, colWidths=[110 * mm, 70 * mm])
    t.setStyle(TableStyle(style))
    story += [t, signature_block("Customer Signature", "Authorized Signature")]
    doc.build(
        story,
        onFirstPage=_header_footer("CUSTOMER INVOICE", [f"Invoice: {d.invoice_no}", f"Date: {when}", f"Customer: {cu.name}"]),
        onLaterPages=_header_footer("CUSTOMER INVOICE", [f"Invoice: {d.invoice_no}", f"Customer: {cu.name}"]),
        canvasmaker=_NumberedCanvas,
    )
    return buf.getvalue()


# --- Text message (WhatsApp / SMS) ----------------------------------------


def invoice_message(d: Delivery, emoji: bool = True) -> str:
    """Neat English invoice text. WhatsApp gets emoji + *bold*; SMS gets plain text."""
    s = get_settings()
    f = _invoice_figures(d)
    when = d.delivery_date.strftime("%d %b %Y") + (f", {d.delivery_time.strftime('%I:%M %p')}" if d.delivery_time else "")
    e = (lambda x: x + " ") if emoji else (lambda x: "")
    b = (lambda x: f"*{x}*") if emoji else (lambda x: x)
    line = "━━━━━━━━━━━━━━━" if emoji else "--------------------"
    unit = "KG" if d.rate_unit.value == "per_kg" else "piece"
    out = [
        f"{e('🐔')}{b(s.company_name)}",
        line,
        f"{e('🧾')}Invoice: {d.invoice_no}",
        f"{e('📅')}Date: {when}",
        f"{e('👤')}Customer: {d.customer.name}",
        line,
        f"{e('🐓')}{d.chicken_type.value.title()} Chicken" + (f" — {d.birds} pieces" if d.birds else ""),
        f"{e('⚖️')}Total weight: {d.net_weight:,.3f} KG",
        f"{e('💰')}Rate: Rs {_n(d.rate)}/{unit}",
        f"Supply amount: Rs {_n(d.amount)}",
    ]
    if d.discount:
        out.append(f"{e('🔻')}Discount (Rs {_n(d.discount_per_kg)}/KG): -Rs {_n(d.discount)}")
        out.append(f"{e('✅')}After discount: Rs {_n(f['after'])}")
    if d.additional_charges:
        out.append(f"Additional charges: Rs {_n(d.additional_charges)}")
    out += [
        line,
        f"{e('📒')}Previous balance: Rs {_n(d.previous_balance)}",
        f"{e('🧮')}Total payable: Rs {_n(f['total_payable'])}",
        f"{e('💵')}Payment received: Rs {_n(d.payment_received)}",
        line,
        f"{e('📌')}{b('Remaining balance: Rs ' + _n(f['remaining']))}",
        "",
        f"Thank you!{' 🙏' if emoji else ''}",
        f"{e('📞')}{s.company_phone}",
    ]
    return "\n".join(out)
