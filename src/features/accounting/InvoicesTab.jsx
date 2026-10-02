import { useEffect, useRef, useState } from "react";
import { BoxInput, BoxSelect, Field } from "../../components/ui/Input";
import { Button } from "../../components/ui/Button";
import { toast } from "../../components/ui/Toast";
import Magnet from "../../components/ui/magnet";
import { useDebounced, usePagedList } from "../../lib/usePagedList";
import { useI18n } from "../../store/i18n";

const EMPTY_FORM = {
  doc_type: "facture",
  client_name: "",
  client_passport: "",
  client_mf: "",
  company_name: "",
  service_type: "",
  issue_date: new Date().toISOString().slice(0, 10),
  tva_rate: "0.19",
  timbre: "1",
  amount_paid: "",
};

const EMPTY_ITEM = { designation: "", quantity: "1", unit_price: "" };

export function InvoicesTab({ country }) {
  const t = useI18n((s) => s.t);
  const [form, setForm] = useState(EMPTY_FORM);
  const [items, setItems] = useState([{ ...EMPTY_ITEM }]);
  const [busy, setBusy] = useState(false);
  // The document being corrected, or null when the form creates a new one.
  const [editing, setEditing] = useState(null);
  const formRef = useRef(null);

  // The list is searched and paged by the server.
  const [query, setQuery] = useState("");
  const q = useDebounced(query.trim(), 300);
  const { items: invoices, total, loading, loadingMore, hasMore, loadMore, reload: load } = usePagedList(
    "/api/invoices",
    { country, q }
  );

  const resetForm = () => {
    setEditing(null);
    setForm(EMPTY_FORM);
    setItems([{ ...EMPTY_ITEM }]);
  };

  // Another country's ledger: whatever was being edited doesn't belong here.
  useEffect(resetForm, [country]);

  const startEdit = (inv) => {
    setEditing(inv);
    setForm({
      doc_type: inv.doc_type,
      client_name: inv.client_name || "",
      client_passport: inv.client_passport || "",
      client_mf: inv.client_mf || "",
      company_name: inv.company_name || "",
      service_type: inv.service_type || "",
      issue_date: inv.issue_date,
      tva_rate: String(inv.tva_rate),
      timbre: String(inv.timbre),
      amount_paid: inv.amount_paid ? String(inv.amount_paid) : "",
    });
    setItems(
      inv.items?.length
        ? inv.items.map((i) => ({ designation: i.designation, quantity: String(i.quantity), unit_price: String(i.unit_price) }))
        : [{ ...EMPTY_ITEM }]
    );
    formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const downloadInvoice = async (inv) => {
    try {
      const res = await fetch(inv.pdf_url);
      if (!res.ok) throw new Error("fail");
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${inv.number}.pdf`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch {
      toast(t("invoicesTab.downloadFailed"), "err");
    }
  };

  const removeInvoice = async (id) => {
    if (!window.confirm(t("invoicesTab.removeConfirm"))) return;
    await fetch(`/api/invoices/${id}`, { method: "DELETE" }).catch(() => {});
    if (editing?.id === id) resetForm();
    load();
  };

  const set = (key) => (e) => setForm((f) => ({ ...f, [key]: e.target.value }));

  const setItem = (i, key) => (e) =>
    setItems((rows) => rows.map((row, idx) => (idx === i ? { ...row, [key]: e.target.value } : row)));

  const addItemRow = () => setItems((rows) => [...rows, { ...EMPTY_ITEM }]);
  const removeItemRow = (i) => setItems((rows) => rows.filter((_, idx) => idx !== i));

  const submit = async (e) => {
    e.preventDefault();
    if (!form.client_name) {
      toast(t("invoicesTab.nameRequired"), "err");
      return;
    }
    setBusy(true);
    try {
      const payload = {
        // The number, country and type of an existing document never change.
        ...(editing ? {} : { country, doc_type: form.doc_type }),
        client_name: form.client_name,
        client_passport: form.client_passport || null,
        client_mf: form.client_mf || null,
        company_name: form.company_name || null,
        service_type: form.service_type || null,
        issue_date: form.issue_date,
        tva_rate: Number(form.tva_rate || 0.19),
        timbre: Number(form.timbre || 1),
        amount_paid: Number(form.amount_paid || 0),
        items:
          form.doc_type === "facture"
            ? items
                .filter((i) => i.designation && i.unit_price)
                .map((i) => ({
                  designation: i.designation,
                  quantity: Number(i.quantity || 1),
                  unit_price: Number(i.unit_price),
                }))
            : [],
      };
      const res = await fetch(editing ? `/api/invoices/${editing.id}` : "/api/invoices", {
        method: editing ? "PUT" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (!res.ok) throw new Error("fail");
      resetForm();
      load();
      toast(t(editing ? "invoicesTab.updated" : "invoicesTab.created"), "ok");
    } catch {
      toast(t(editing ? "invoicesTab.updateFailed" : "invoicesTab.createFailed"), "err");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
      <form ref={formRef} onSubmit={submit} className="card">
        {editing ? (
          <p style={{ marginBottom: "14px", fontSize: "14px", fontWeight: "700", color: "var(--color-brand)" }}>
            {t("invoicesTab.editing")} {editing.number}
            <span style={{ marginInlineStart: "10px", fontSize: "12px", fontWeight: "500", color: "var(--color-muted)" }}>
              {t("invoicesTab.lockedHint")}
            </span>
          </p>
        ) : null}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "12px" }}>
          <Field label={t("invoicesTab.docType")}>
            <BoxSelect value={form.doc_type} onChange={set("doc_type")} disabled={Boolean(editing)}>
              <option value="facture">{t("invoicesTab.facture")}</option>
              <option value="recu">{t("invoicesTab.recu")}</option>
            </BoxSelect>
          </Field>
          <Field label={t("invoicesTab.clientName")}>
            <BoxInput value={form.client_name} onChange={set("client_name")} />
          </Field>
          <Field label={t("invoicesTab.clientPassport")}>
            <BoxInput value={form.client_passport} onChange={set("client_passport")} />
          </Field>
          <Field label={t("invoicesTab.matriculeFiscal")}>
            <BoxInput value={form.client_mf} onChange={set("client_mf")} />
          </Field>
          <Field label={t("invoicesTab.companyName")}>
            <BoxInput value={form.company_name} onChange={set("company_name")} />
          </Field>
          {form.doc_type === "recu" ? (
            <Field label={t("invoicesTab.serviceType")}>
              <BoxInput value={form.service_type} onChange={set("service_type")} />
            </Field>
          ) : null}
          <Field label={t("invoicesTab.issueDate")}>
            <BoxInput type="date" value={form.issue_date} onChange={set("issue_date")} />
          </Field>
          {form.doc_type === "facture" ? (
            <>
              <Field label={t("invoicesTab.tvaRate")}>
                <BoxInput type="number" step="0.01" value={form.tva_rate} onChange={set("tva_rate")} />
              </Field>
              <Field label={t("invoicesTab.timbre")}>
                <BoxInput type="number" step="0.01" value={form.timbre} onChange={set("timbre")} />
              </Field>
            </>
          ) : null}
          <Field label={t("invoicesTab.amountPaid")}>
            <BoxInput type="number" step="0.01" value={form.amount_paid} onChange={set("amount_paid")} />
          </Field>
        </div>

        {form.doc_type === "facture" ? (
          <div style={{ marginTop: "20px" }}>
            <p style={{ fontSize: "13px", fontWeight: "700", color: "var(--color-ink)", marginBottom: "8px" }}>{t("invoicesTab.lineItems")}</p>
            {items.map((row, i) => (
              <div key={i} style={{ display: "grid", gridTemplateColumns: "2fr 1fr 1fr auto", gap: "10px", marginBottom: "8px" }}>
                <BoxInput placeholder={t("invoicesTab.designation")} value={row.designation} onChange={setItem(i, "designation")} />
                <BoxInput type="number" placeholder={t("invoicesTab.qty")} value={row.quantity} onChange={setItem(i, "quantity")} />
                <BoxInput type="number" step="0.01" placeholder={t("invoicesTab.unitPrice")} value={row.unit_price} onChange={setItem(i, "unit_price")} />
                <button type="button" onClick={() => removeItemRow(i)} style={{ color: "var(--color-danger)", fontWeight: "600", fontSize: "12px" }}>
                  {t("common.remove")}
                </button>
              </div>
            ))}
            <button type="button" onClick={addItemRow} style={{ fontSize: "13px", fontWeight: "600", color: "var(--color-brand)" }}>
              {t("invoicesTab.addLineItem")}
            </button>
          </div>
        ) : null}

        <div style={{ marginTop: "20px", display: "flex", gap: "10px", alignItems: "center" }}>
          <div style={{ flex: 1, maxWidth: "320px" }}>
            <Button variant="brand" type="submit" loading={busy}>
              {editing
                ? t("invoicesTab.saveChanges")
                : form.doc_type === "recu"
                ? t("invoicesTab.createRecu")
                : t("invoicesTab.createFacture")}
            </Button>
          </div>
          {editing ? (
            <div style={{ width: "140px" }}>
              <Button variant="ghost" onClick={resetForm}>
                {t("invoicesTab.cancelEdit")}
              </Button>
            </div>
          ) : null}
        </div>
      </form>

      <div className="card" style={{ padding: 0, overflow: "hidden" }}>
        <div style={{ padding: "16px 20px", borderBottom: "1px solid var(--color-line)", display: "flex", flexWrap: "wrap", gap: "12px", alignItems: "center", justifyContent: "space-between" }}>
          <h2 style={{ fontSize: "16px", fontWeight: "700" }}>{t("invoicesTab.documentsFor")} — {t(`countries.${country}`)}</h2>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t("invoicesTab.searchPlaceholder")}
            className="input-box"
            style={{ maxWidth: "280px" }}
          />
        </div>
        <table className="data-table">
          <thead>
            <tr>
              <th>{t("invoicesTab.number")}</th>
              <th>{t("invoicesTab.type")}</th>
              <th>{t("invoicesTab.client")}</th>
              <th>{t("invoicesTab.date")}</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {invoices.length === 0 ? (
              <tr>
                <td colSpan={5} style={{ padding: "32px 16px", textAlign: "center", color: "var(--color-muted)" }}>
                  {loading ? t("common.loading") : t("invoicesTab.noDocuments")}
                </td>
              </tr>
            ) : (
              invoices.map((inv) => (
                <tr key={inv.id}>
                  <td style={{ fontWeight: "600" }}>{inv.number}</td>
                  <td>{inv.doc_type === "recu" ? t("invoicesTab.recu") : t("invoicesTab.facture")}</td>
                  <td>{inv.client_name}</td>
                  <td>{inv.issue_date}</td>
                  <td style={{ display: "flex", gap: "8px" }}>
                    <Magnet padding={22} magnetStrength={14}>
                      <button
                        type="button"
                        onClick={() => downloadInvoice(inv)}
                        className="btn btn-brand"
                        style={{ width: "auto", padding: "6px 14px", fontSize: "12px", display: "inline-flex" }}
                      >
                        {t("invoicesTab.downloadPdf")}
                      </button>
                    </Magnet>
                    <button
                      type="button"
                      onClick={() => startEdit(inv)}
                      style={{ color: "var(--color-brand)", fontSize: "12px", fontWeight: "600" }}
                    >
                      {t("invoicesTab.edit")}
                    </button>
                    <button
                      type="button"
                      onClick={() => removeInvoice(inv.id)}
                      style={{ color: "var(--color-danger)", fontSize: "12px", fontWeight: "600" }}
                    >
                      {t("invoicesTab.remove")}
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        {total > 0 ? (
          <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: "16px", padding: "14px", borderTop: "1px solid var(--color-line)" }}>
            <span style={{ fontSize: "13px", color: "var(--color-muted)" }}>
              {t("clients.showing").replace("{n}", invoices.length).replace("{total}", total)}
            </span>
            {hasMore ? (
              <button type="button" className="btn btn-ghost" style={{ width: "auto", padding: "8px 18px" }} onClick={loadMore} disabled={loadingMore}>
                {loadingMore ? t("common.loading") : t("clients.loadMore")}
              </button>
            ) : null}
          </div>
        ) : null}
      </div>
    </div>
  );
}
