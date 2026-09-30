import { useEffect, useRef } from "react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { ChatbotPanel } from "../features/chatbot/ChatbotPanel";
import { ChatFab } from "../components/ChatFab";
import { NotificationBell } from "../components/NotificationBell";
import { GlobalSearch } from "../components/GlobalSearch";
import { ThemeToggle } from "../components/ThemeToggle";
import { LangToggle } from "../components/LangToggle";
import Magnet from "../components/ui/magnet";
import {
  IconBot,
  IconChart,
  IconClipboard,
  IconGrid,
  IconLedger,
  IconLogout,
  IconMenu,
  IconPeople,
  IconShield,
  IconUsersGear,
  IconWallet,
  LogoMark,
} from "../components/ui/Icons";
import { DURATION, EASE, ScrollTrigger, gsap, useGSAP } from "../lib/gsap";
import { destroyLenis, initLenis } from "../lib/lenis";
import { useAuth } from "../store/auth";
import { useUi } from "../store/ui";
import { useI18n } from "../store/i18n";
import { RouteTransition } from "./RouteTransition";

function navAccountItems(t) {
  return [
    { to: "/", label: t("nav.dashboard"), icon: IconGrid, end: true },
    { to: "/stats", label: t("nav.stats"), icon: IconChart },
    { to: "/clients", label: t("nav.clients"), icon: IconPeople },
    { to: "/accounting/tunisia", label: t("nav.accountingTn"), icon: IconLedger },
    { to: "/accounting/libya", label: t("nav.accountingLy"), icon: IconLedger },
  ];
}

function navHrItems(t) {
  return [
    { to: "/MyRequests", label: t("nav.myRequests"), icon: IconClipboard },
    { to: "/EmployeeRequests", label: t("nav.employeeRequests"), icon: IconUsersGear },
    { to: "/Payroll", label: t("nav.payroll"), icon: IconWallet },
    { to: "/Users", label: t("nav.users"), icon: IconShield },
  ];
}

export function AppShell() {
  const sidebarRef = useRef(null);
  const scrollRef = useRef(null);
  const location = useLocation();
  const navigate = useNavigate();
  const user = useAuth((s) => s.user);
  const logout = useAuth((s) => s.logout);
  const sidebarOpen = useUi((s) => s.sidebarOpen);
  const toggleSidebar = useUi((s) => s.toggleSidebar);
  const t = useI18n((s) => s.t);

  useGSAP(
    (context, contextSafe) => {
      const el = sidebarRef.current;
      if (!el) return;
      const labels = el.querySelectorAll("[data-label]");
      const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      // Below 900px the sidebar is a full-height overlay drawer (see
      // layout.css) instead of a column that pushes content over — so it's
      // either fully open (240px) or fully hidden (0), never a collapsed
      // icon rail, which would otherwise permanently eat a chunk of a phone
      // screen's width.
      const isMobile = window.matchMedia("(max-width: 899px)").matches;
      const width = isMobile ? (sidebarOpen ? 240 : 0) : sidebarOpen ? 232 : 76;
      gsap.to(el, {
        width,
        duration: reduce ? 0 : DURATION,
        ease: EASE,
        onComplete: contextSafe(() => ScrollTrigger.refresh()),
      });
      gsap.to(labels, {
        autoAlpha: sidebarOpen ? 1 : 0,
        x: sidebarOpen ? 0 : -6,
        duration: reduce ? 0 : 0.28,
        ease: EASE,
        stagger: sidebarOpen ? 0.02 : 0,
      });
    },
    { dependencies: [sidebarOpen], scope: sidebarRef }
  );

  // Tapping a nav link inside the mobile overlay drawer should close it —
  // otherwise it stays covering the new page until the user taps again.
  const closeSidebarOnMobile = () => {
    if (window.matchMedia("(max-width: 899px)").matches) toggleSidebar();
  };

  useEffect(() => {
    const node = scrollRef.current;
    if (!node) return;
    initLenis(node);
    return () => destroyLenis();
  }, []);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0 });
    requestAnimationFrame(() => ScrollTrigger.refresh());
  }, [location.pathname]);

  const isAdmin = user?.role === "Admin";
  const NAV_ACCOUNT = navAccountItems(t);
  const NAV_HR = navHrItems(t);
  const navAccount = isAdmin ? NAV_ACCOUNT : NAV_ACCOUNT.slice(0, 3);
  const navHr = isAdmin ? NAV_HR : NAV_HR.filter((item) => item.to === "/EmployeeRequests");

  const initials = (user?.name || "AG")
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join("");

  return (
    <div className="app-shell">
      <aside
        ref={sidebarRef}
        className={`app-sidebar ${sidebarOpen ? "" : "collapsed"}`}
      >
        <div className="sidebar-header">
          <img
            src="./logo.png"
            alt={t("shell.logo")}
            className="sidebar-logo"
          />
          <div data-label className="sidebar-header-text">
            <span className="sidebar-brand-text">
              TCA
            </span>
            <span style={{ whiteSpace: "nowrap", color: "var(--color-muted)", fontSize: "10px" }}>
              {t("shell.tagline")}
            </span>
          </div>
        </div>

        <hr className="sidebar-divider" />

        <nav className="sidebar-nav">
          {navAccount.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                title={item.label}
                onClick={closeSidebarOnMobile}
                className={({ isActive }) =>
                  `nav-link ${isActive ? "active" : ""}`
                }
              >
                <Icon size={18} style={{ flexShrink: 0 }} />
                <span data-label style={{ whiteSpace: "nowrap" }}>
                  {item.label}
                </span>
              </NavLink>
            );
          })}

          <hr className="sidebar-divider" />

          {navHr.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                title={item.label}
                onClick={closeSidebarOnMobile}
                className={({ isActive }) =>
                  `nav-link ${isActive ? "active" : ""}`
                }
              >
                <Icon size={18} style={{ flexShrink: 0 }} />
                <span data-label style={{ whiteSpace: "nowrap" }}>
                  {item.label}
                </span>
              </NavLink>
            );
          })}

          <hr className="sidebar-divider" />

          <button
            type="button"
            onClick={() => {
              navigate("/chatbot");
              closeSidebarOnMobile();
            }}
            className="nav-link"
            title={t("nav.aiChatbot")}
            style={{ width: "100%", textAlign: "left" }}
          >
            <IconBot size={18} style={{ flexShrink: 0 }} />
            <span data-label style={{ whiteSpace: "nowrap" }}>
              {t("nav.aiChatbot")}
            </span>
          </button>
        </nav>

        <p data-label className="sidebar-footer">
          {t("shell.footer")}
        </p>
      </aside>

      {sidebarOpen ? <div className="sidebar-backdrop" onClick={toggleSidebar} /> : null}

      <div className="app-main-column">
        <header className="app-header">
          <div className="header-left">
            <Magnet padding={22} magnetStrength={14}>
              <button
                type="button"
                onClick={toggleSidebar}
                className="icon-btn"
                aria-label={t("shell.toggleSidebar")}
              >
                <IconMenu />
              </button>
            </Magnet>
            <GlobalSearch />
          </div>

          <div className="header-right">
            <LangToggle />
            <ThemeToggle />
            <NotificationBell />
            <div className="user-badge">
              <div className="avatar-circle">
                {initials || "AG"}
              </div>
              <div className="user-info-text">
                <p className="user-name">{user?.name || "Agent"}</p>
                <p className="user-role">{user?.role}</p>
              </div>
              <Magnet padding={22} magnetStrength={14}>
                <button
                  type="button"
                  onClick={() => {
                    logout();
                    navigate("/login");
                  }}
                  className="btn-logout"
                >
                  <IconLogout size={14} />
                  <span className="btn-logout-label">{t("header.logout")}</span>
                </button>
              </Magnet>
            </div>
          </div>
        </header>

        <main ref={scrollRef} className="app-main-scroll">
          <div className="app-page-padding">
            <RouteTransition>
              <Outlet />
            </RouteTransition>
          </div>
        </main>
      </div>

      <ChatbotPanel />
      <ChatFab />
    </div>
  );
}