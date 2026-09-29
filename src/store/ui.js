import { create } from "zustand";

// Below 900px the sidebar becomes an overlay drawer (see layout.css) rather
// than a permanent column, so it starts closed there — a full-width drawer
// covering the screen on first paint would be worse than no sidebar at all.
const startsOpen = typeof window === "undefined" || window.innerWidth >= 900;

export const useUi = create((set) => ({
  sidebarOpen: startsOpen,
  chatbotOpen: false,
  search: "",
  notifications: [
    { id: 1, text: "3 documents pending review", time: "12m" },
    { id: 2, text: "Invoice #1042 is overdue", time: "1h" },
    { id: 3, text: "New client request: Marwan A.", time: "3h" },
  ],
  toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
  setSidebar: (sidebarOpen) => set({ sidebarOpen }),
  toggleChatbot: () => set((s) => ({ chatbotOpen: !s.chatbotOpen })),
  setChatbot: (chatbotOpen) => set({ chatbotOpen }),
  setSearch: (search) => set({ search }),
}));
