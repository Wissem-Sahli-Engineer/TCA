import { useEffect, useState } from "react";
import { BoxInput, Field } from "../../components/ui/Input";
import { Button } from "../../components/ui/Button";
import { toast } from "../../components/ui/Toast";
import { useI18n } from "../../store/i18n";

const EMPTY_ACCOUNT = { name: "", currency: "", balance: "" };
const EMPTY_TX = { label: "", amount: "", entry_date: new Date().toISOString().slice(0, 10) };

export function BankingTab({ country, currency, flag }) {
  const t = useI18n((s) => s.t);
  const [accounts, setAccounts] = useState([]);
  const [selected, setSelected] = useState(null);
  const [transactions, setTransactions] = useState([]);

  const [accountForm, setAccountForm] = useState(EMPTY_ACCOUNT);
  const [txForm, setTxForm] = useState(EMPTY_TX);
  const [busy, setBusy] = useState(false);

  const loadAccounts = () => {
    fetch(`/api/banking/accounts?country=${country}`)
      .then((r) => (r.ok ? r.json() : []))
      .then(setAccounts)
      .catch(() => setAccounts([]));
  };

  useEffect(() => {
    loadAccounts();
    setSelected(null);
  }, [country]);

  const loadTransactions = (accountId) => {
    fetch(`/api/banking/accounts/${accountId}/transactions`)
      .then((r) => (r.ok ? r.json() : []))
      .then(setTransactions)
      .catch(() => setTransactions([]));
  };

  useEffect(() => {
    if (!selected) {
      setTransactions([]);
      return;
    }
    loadTransactions(selected.id);
  }, [selected]);

  const addAccount = async (e) => {
    e.preventDefault();
    if (!accountForm.name || !accountForm.currency) return;
    setBusy(true);
    try {
      await fetch("/api/banking/accounts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          country,
          name: accountForm.name,
          currency: accountForm.currency,
          balance: Number(accountForm.balance || 0),
        }),
      });
      setAccountForm(EMPTY_ACCOUNT);
      loadAccounts();
      toast(t("bankingTab.accountAdded"), "ok");
    } catch {
      toast(t("bankingTab.addAccountFailed"), "err");
    } finally {
      setBusy(false);
    }
  };

  const removeAccount = async (id) => {
    if (!window.confirm(t("bankingTab.removeAccountConfirm"))) return;
    await fetch(`/api/banking/accounts/${id}`, { method: "DELETE" }).catch(() => {});
    if (selected?.id === id) setSelected(null);
    loadAccounts();
  };

  const addTransaction = async (e) => {
    e.preventDefault();
    if (!selected || !txForm.label || !txForm.amount) return;
    setBusy(true);
    try {
      await fetch(`/api/banking/accounts/${selected.id}/transactions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          account_id: selected.id,
          label: txForm.label,
          amount: Number(txForm.amount),
          entry_date: txForm.entry_date,
        }),
      });
      setTxForm(EMPTY_TX);
      loadAccounts();
      loadTransactions(selected.id);
      toast(t("bankingTab.txRecorded"), "ok");
    } catch {
      toast(t("bankingTab.txFailed"), "err");
    } finally {
      setBusy(false);
    }
  };

  const removeTransaction = async (txId) => {
    if (!selected) return;
    await fetch(`/api/banking/accounts/${selected.id}/transactions/${txId}`, { method: "DELETE" }).catch(() => {});
    loadAccounts();
    loadTransactions(selected.id);
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
      <div>
        <h2 style={{ fontSize: "18px", fontWeight: "700", marginBottom: "12px" }}>{t("bankingTab.bankAccounts")}</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: "16px" }}>
          {accounts.map((a, i) => (
            <div
              key={a.id}
              className={i === 0 ? "card-ink" : "card"}
              style={{ padding: "20px", cursor: "pointer", outline: selected?.id === a.id ? "2px solid var(--color-brand)" : "none", position: "relative" }}
              onClick={() => setSelected(a)}
            >
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  removeAccount(a.id);
                }}
                style={{
                  position: "absolute", top: "12px", right: "12px", fontSize: "11px", fontWeight: "700",
                  color: i === 0 ? "var(--color-card-ink-text)" : "var(--color-danger)",
                  opacity: i === 0 ? 0.7 : 1,
                }}
              >
                {t("bankingTab.remove")}
              </button>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <p style={{ fontSize: "11px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.14em", color: i === 0 ? "var(--color-card-ink-text)" : "var(--color-muted)", opacity: i === 0 ? 0.6 : 1 }}>
                  {a.currency} {t("bankingTab.accountSuffix")}
                </p>
                <span style={{ fontSize: "16px" }}>{flag}</span>
              </div>
              <h3 style={{ marginTop: "8px", fontSize: "17px", fontWeight: "700" }}>{a.name}</h3>
              <p style={{ marginTop: "20px", fontSize: "28px", fontWeight: "800" }}>
                {a.currency} {a.balance.toLocaleString()}
              </p>
            </div>
          ))}
          {accounts.length === 0 ? (
            <p style={{ color: "var(--color-muted)", fontSize: "14px" }}>{t("bankingTab.noAccounts")} {t(`countries.${country}`)}.</p>
          ) : null}
        </div>

        <form onSubmit={addAccount} className="card" style={{ marginTop: "16px", display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: "12px", alignItems: "end" }}>
          <Field label={t("bankingTab.accountName")}>
            <BoxInput value={accountForm.name} onChange={(e) => setAccountForm((f) => ({ ...f, name: e.target.value }))} />
          </Field>
          <Field label={t("bankingTab.currency")}>
            <BoxInput value={accountForm.currency} onChange={(e) => setAccountForm((f) => ({ ...f, currency: e.target.value }))} placeholder={currency} />
          </Field>
          <Field label={t("bankingTab.openingBalance")}>
            <BoxInput type="number" step="0.01" value={accountForm.balance} onChange={(e) => setAccountForm((f) => ({ ...f, balance: e.target.value }))} />
          </Field>
          <Button variant="brand" type="submit" loading={busy}>
            {t("bankingTab.addAccount")}
          </Button>
        </form>
      </div>

      {selected ? (
        <div>
          <h2 style={{ fontSize: "18px", fontWeight: "700", marginBottom: "12px" }}>
            {t("bankingTab.transactionsFor")} {selected.name}
          </h2>
          <form onSubmit={addTransaction} className="card" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: "12px", alignItems: "end", marginBottom: "16px" }}>
            <Field label={t("bankingTab.label")}>
              <BoxInput value={txForm.label} onChange={(e) => setTxForm((f) => ({ ...f, label: e.target.value }))} />
            </Field>
            <Field label={t("bankingTab.amount")}>
              <BoxInput type="number" step="0.01" value={txForm.amount} onChange={(e) => setTxForm((f) => ({ ...f, amount: e.target.value }))} />
            </Field>
            <Field label={t("bankingTab.date")}>
              <BoxInput type="date" value={txForm.entry_date} onChange={(e) => setTxForm((f) => ({ ...f, entry_date: e.target.value }))} />
            </Field>
            <Button variant="brand" type="submit" loading={busy}>
              {t("bankingTab.addTransaction")}
            </Button>
          </form>
          <div className="card" style={{ padding: 0, overflow: "hidden" }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>{t("bankingTab.labelCol")}</th>
                  <th>{t("bankingTab.amountCol")}</th>
                  <th>{t("bankingTab.dateCol")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {transactions.length === 0 ? (
                  <tr>
                    <td colSpan={4} style={{ padding: "24px 16px", textAlign: "center", color: "var(--color-muted)" }}>
                      {t("bankingTab.noTransactions")}
                    </td>
                  </tr>
                ) : (
                  transactions.map((tx) => (
                    <tr key={tx.id}>
                      <td>{tx.label}</td>
                      <td style={{ color: tx.amount < 0 ? "var(--color-danger)" : "var(--color-success)", fontWeight: "600" }}>
                        {tx.amount > 0 ? "+" : ""}{tx.amount.toLocaleString()}
                      </td>
                      <td>{tx.entry_date}</td>
                      <td>
                        <button type="button" onClick={() => removeTransaction(tx.id)} style={{ color: "var(--color-danger)", fontSize: "12px", fontWeight: "600" }}>
                          {t("bankingTab.remove")}
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}
    </div>
  );
}
