import { useRef, useState } from "react";
import { IconClose, IconSend } from "../../components/ui/Icons";
import { DURATION, EASE, gsap, useGSAP } from "../../lib/gsap";
import { useUi } from "../../store/ui";
import { CHAT_API_URL } from "../../lib/config";
import { captureScreenshot } from "../../lib/screenCapture";
import { useI18n } from "../../store/i18n";

export function ChatbotPanel() {
  const t = useI18n((s) => s.t);
  const isRtl = useI18n((s) => s.isRtl);
  const open = useUi((s) => s.chatbotOpen);
  const setChatbot = useUi((s) => s.setChatbot);
  const panelRef = useRef(null);
  const [messages, setMessages] = useState(() => [{ role: "assistant", content: t("chatbot.panelStarter") }]);
  const [draft, setDraft] = useState("");
  const [liveHelper, setLiveHelper] = useState(false);
  const [loading, setLoading] = useState(false);

  useGSAP(
    () => {
      const el = panelRef.current;
      if (!el) return;
      const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      gsap.to(el, {
        x: open ? 0 : isRtl ? -420 : 420,
        autoAlpha: open ? 1 : 0,
        duration: reduce ? 0 : DURATION,
        ease: EASE,
        pointerEvents: open ? "auto" : "none",
      });
    },
    { dependencies: [open, isRtl] }
  );

  const send = async (e) => {
    e.preventDefault();
    const text = draft.trim();
    if (!text || loading) return;

    let image;
    let captureError;
    if (liveHelper) {
      try {
        image = await captureScreenshot();
      } catch (err) {
        captureError = err.message;
      }
    }

    const next = [...messages, { role: "user", content: text }];
    setMessages(next);
    setDraft("");
    setLoading(true);

    try {
      const res = await fetch(CHAT_API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages: next, image }),
      });
      if (!res.ok) throw new Error(`request failed (${res.status})`);
      const data = await res.json();
      const prefix = captureError ? t("chatbot.screenShareFailed").replace("{error}", captureError) + "\n" : "";
      setMessages((m) => [...m, { role: "assistant", content: prefix + (data.reply || t("chatbot.noResponse")) }]);
    } catch (err) {
      setMessages((m) => [...m, { role: "assistant", content: t("chatbot.panelUnreachable").replace("{error}", err.message) }]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <aside
      ref={panelRef}
      style={{
        position: "fixed",
        bottom: "calc(96px + env(safe-area-inset-bottom))",
        insetInlineEnd: "24px",
        zIndex: 40,
        display: "flex",
        height: "min(560px, 70vh)",
        width: "min(380px, calc(100vw - 32px))",
        transform: `translateX(${isRtl ? -420 : 420}px)`,
        flexDirection: "column",
        overflow: "hidden",
        borderRadius: "var(--radius-card)",
        border: "1px solid var(--color-line)",
        backgroundColor: "var(--color-white)",
        opacity: 0,
        boxShadow: "var(--shadow-login)",
      }}
    >
      <div
        className="flex-between"
        style={{ borderBottom: "1px solid var(--color-line)", padding: "16px 20px" }}
      >
        <div>
          <p style={{ fontSize: "11px", fontWeight: "600", textTransform: "uppercase", letterSpacing: "0.14em", color: "var(--color-muted)" }}>
            {t("chatbot.internal")}
          </p>
          <h2 style={{ fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>{t("chatbot.panelTitle")}</h2>
        </div>
        <button
          type="button"
          onClick={() => setChatbot(false)}
          className="icon-btn"
          aria-label={t("chatbot.closeChatbot")}
        >
          <IconClose />
        </button>
      </div>

      <label
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: "8px",
          padding: "10px 20px",
          borderBottom: "1px solid var(--color-line)",
          fontSize: "12.5px",
          fontWeight: "600",
          color: "var(--color-muted)",
          cursor: "pointer",
        }}
      >
        <span>{t("chatbot.liveHelper")}</span>
        <input
          type="checkbox"
          checked={liveHelper}
          onChange={(e) => setLiveHelper(e.target.checked)}
        />
      </label>

      <div
        style={{
          flex: 1,
          overflowY: "auto",
          padding: "20px",
          display: "flex",
          flexDirection: "column",
          gap: "12px",
        }}
      >
        {messages.map((m, i) => (
          <div
            key={i}
            style={{
              maxWidth: "85%",
              borderRadius: "14px",
              padding: "10px 14px",
              fontSize: "13px",
              lineHeight: "1.45",
              backgroundColor: m.role === "assistant" ? "var(--color-surface)" : "var(--color-ink)",
              color: m.role === "assistant" ? "var(--color-ink)" : "var(--color-white)",
              marginInlineStart: m.role === "assistant" ? 0 : "auto",
              whiteSpace: "pre-wrap",
            }}
          >
            {m.content}
          </div>
        ))}
        {loading ? (
          <div
            style={{
              maxWidth: "85%",
              borderRadius: "14px",
              padding: "10px 14px",
              fontSize: "13px",
              backgroundColor: "var(--color-surface)",
              color: "var(--color-muted)",
            }}
          >
            {t("chatbot.thinking")}
          </div>
        ) : null}
      </div>

      <form
        onSubmit={send}
        style={{
          display: "flex",
          gap: "8px",
          borderTop: "1px solid var(--color-line)",
          padding: "12px",
        }}
      >
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              send(e);
            }
          }}
          placeholder={t("chatbot.askPlaceholder")}
          className="input-box"
          style={{ flex: 1 }}
        />
        <button
          type="submit"
          className="btn btn-brand"
          style={{ width: "auto", padding: "10px 14px" }}
          aria-label={t("chatbot.send")}
          disabled={loading}
        >
          <IconSend />
        </button>
      </form>
    </aside>
  );
}
