import { useEffect, useRef, useState } from "react";
import { PageTitle } from "../../components/ui/Card";
import { IconSend } from "../../components/ui/Icons";
import { CHAT_API_URL, CHAT_MODEL_LABEL } from "../../lib/config";
import { useChatStore } from "../../store/chat";
import { useLenisScroll } from "../../lib/useLenisScroll";
import Magnet from "../../components/ui/magnet";
import { useI18n } from "../../store/i18n";

export function ChatbotPage() {
  const t = useI18n((s) => s.t);
  const STARTER = [
    { role: "assistant", content: t("chatbot.starter").replace("{model}", CHAT_MODEL_LABEL) },
  ];
  const messages = useChatStore((s) => s.pageMessages);
  const setMessages = useChatStore((s) => s.setPageMessages);
  const [draft, setDraft] = useState("");
  const [loading, setLoading] = useState(false);
  const scrollRef = useRef(null);

  useLenisScroll(scrollRef);

  useEffect(() => {
    if (messages.length === 0) setMessages(STARTER);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const node = scrollRef.current;
    if (!node) return;
    requestAnimationFrame(() => {
      node.scrollTop = node.scrollHeight;
    });
  }, [messages, loading]);

  const send = async (e) => {
    e.preventDefault();
    const text = draft.trim();
    if (!text || loading) return;

    const next = [...messages, { role: "user", content: text }];
    setMessages(next);
    setDraft("");
    setLoading(true);

    try {
      const res = await fetch(CHAT_API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages: next }),
      });
      if (!res.ok) throw new Error(`request failed (${res.status})`);
      const data = await res.json();
      setMessages((m) => [...m, { role: "assistant", content: data.reply || t("chatbot.noResponse") }]);
    } catch (err) {
      setMessages((m) => [
        ...m,
        {
          role: "assistant",
          content: t("chatbot.unreachable").replace("{error}", err.message),
        },
      ]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="page-container-max"
      style={{
        display: "flex",
        flexDirection: "column",
        height: "calc(100vh - 134px - env(safe-area-inset-top) - env(safe-area-inset-bottom))",
      }}
    >
      <PageTitle kicker={t("chatbot.kicker")} title={t("chatbot.title")} />

      <div
        className="card"
        style={{
          flex: 1,
          minHeight: 0,
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
          padding: 0,
        }}
      >
        <div ref={scrollRef} style={{ flex: 1, minHeight: 0, overflowY: "auto" }}>
          <div style={{ display: "flex", flexDirection: "column", gap: "14px", padding: "24px" }}>
            {messages.map((m, i) => (
              <div
                key={i}
                style={{
                  maxWidth: "70%",
                  borderRadius: "14px",
                  padding: "12px 16px",
                  fontSize: "14px",
                  lineHeight: "1.5",
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
                  maxWidth: "70%",
                  borderRadius: "14px",
                  padding: "12px 16px",
                  fontSize: "14px",
                  backgroundColor: "var(--color-surface)",
                  color: "var(--color-muted)",
                }}
              >
                {t("chatbot.thinking")}
              </div>
            ) : null}
          </div>
        </div>

        <form
          onSubmit={send}
          style={{
            display: "flex",
            flexShrink: 0,
            gap: "10px",
            borderTop: "1px solid var(--color-line)",
            padding: "16px",
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
          <Magnet padding={30} magnetStrength={14}>
            <button
              type="submit"
              className="btn btn-brand"
              style={{ width: "auto", padding: "10px 16px" }}
              aria-label={t("chatbot.send")}
              disabled={loading}
            >
              <IconSend />
            </button>
          </Magnet>
        </form>
      </div>
    </div>
  );
}
