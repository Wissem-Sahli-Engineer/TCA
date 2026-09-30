import React, { useState } from 'react';
import styled from 'styled-components';

const DEFAULT_ICONS = {
  invoices: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <path d="M14 2v6h6" />
      <path d="M16 13H8" />
      <path d="M16 17H8" />
      <path d="M10 9H8" />
    </svg>
  ),
  treasury: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="6" width="20" height="12" rx="2" />
      <circle cx="12" cy="12" r="2" />
      <path d="M6 12h.01M18 12h.01" />
    </svg>
  ),
  banking: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 21h18" />
      <path d="M3 10h18" />
      <path d="M5 6l7-3 7 3" />
      <path d="M4 10v11" />
      <path d="M20 10v11" />
      <path d="M8 14v4" />
      <path d="M12 14v4" />
      <path d="M16 14v4" />
    </svg>
  ),
  stats: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 3v18h18" />
      <path d="M18 17V9" />
      <path d="M13 17V5" />
      <path d="M8 17v-3" />
    </svg>
  ),
  normal: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
      <path fillRule="evenodd" d="M7.5 6a4.5 4.5 0 1 1 9 0 4.5 4.5 0 0 1-9 0ZM3.751 20.105a8.25 8.25 0 0 1 16.498 0 .75.75 0 0 1-.437.695A18.683 18.683 0 0 1 12 22.5c-2.786 0-5.433-.6-7.812-1.7a.75.75 0 0 1-.437-.695Z" clipRule="evenodd" />
    </svg>
  ),
  fair: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
      <path fillRule="evenodd" d="M11.47 2.47a.75.75 0 0 1 1.06 0l9 9a.75.75 0 0 1-.53 1.28H3a.75.75 0 0 1-.53-1.28l9-9Z" />
      <path fillRule="evenodd" d="M3 14.25a.75.75 0 0 1 .75-.75h16.5a.75.75 0 0 1 0 1.5H3.75a.75.75 0 0 1-.75-.75ZM4.5 16.5a.75.75 0 0 1 .75.75v3.75a.75.75 0 0 1-1.5 0V17.25a.75.75 0 0 1 .75-.75Zm5 0a.75.75 0 0 1 .75.75v3.75a.75.75 0 0 1-1.5 0V17.25a.75.75 0 0 1 .75-.75Zm5 0a.75.75 0 0 1 .75.75v3.75a.75.75 0 0 1-1.5 0V17.25a.75.75 0 0 1 .75-.75Zm5 0a.75.75 0 0 1 .75.75v3.75a.75.75 0 0 1-1.5 0V17.25a.75.75 0 0 1 .75-.75ZM2.25 22.5h19.5a.75.75 0 0 0 0-1.5H2.25a.75.75 0 0 0 0 1.5Z" clipRule="evenodd" />
    </svg>
  ),
  reservation: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
      <path fillRule="evenodd" d="M4.5 2.25a.75.75 0 0 0-.75.75v18a.75.75 0 0 0 .75.75h15a.75.75 0 0 0 .75-.75V3a.75.75 0 0 0-.75-.75h-15ZM7.5 6a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-.75.75h-1.5A.75.75 0 0 1 7.5 7.5V6Zm6 0a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-.75.75h-1.5A.75.75 0 0 1 13.5 7.5V6ZM7.5 12a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-.75.75h-1.5A.75.75 0 0 1 7.5 13.5V12Zm6 0a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-.75.75h-1.5A.75.75 0 0 1 13.5 12Zm-3.75 5.25a.75.75 0 0 0-.75.75v3h4.5v-3a.75.75 0 0 0-.75-.75h-3Z" clipRule="evenodd" />
    </svg>
  ),
  alert: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
      <path fillRule="evenodd" d="M9.401 3.003c1.155-2 4.043-2 5.197 0l7.355 12.748c1.154 2-.29 4.5-2.599 4.5H4.645c-2.309 0-3.752-2.5-2.598-4.5L9.4 3.003ZM12 8.25a.75.75 0 0 1 .75.75v3.75a.75.75 0 0 1-1.5 0V9a.75.75 0 0 1 .75-.75Zm0 8.25a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" clipRule="evenodd" />
    </svg>
  ),
};

const DEFAULT_CLIENT_TABS = [
  { id: 'normal', label: 'Normal' },
  { id: 'fair', label: 'Fair' },
  { id: 'reservation', label: 'Reservation' },
  { id: 'alert', label: 'Alert' },
];

export const Card = ({ tabs, activeTab, onTabChange, maxWidth = 520 }) => {
  const tabList = tabs || DEFAULT_CLIENT_TABS;
  const [internalTab, setInternalTab] = useState(tabList[0]?.id || 'normal');
  const current = activeTab !== undefined ? activeTab : internalTab;

  const handleClick = (id) => (e) => {
    e.preventDefault();
    setInternalTab(id);
    if (onTabChange) onTabChange(id);
  };

  return (
    <StyledWrapper $maxWidth={maxWidth}>
      <div className="menu">
        {tabList.map((t) => {
          const icon = t.icon || DEFAULT_ICONS[t.id] || DEFAULT_ICONS.normal;
          const isActive = current === t.id;
          return (
            <button
              key={t.id}
              type="button"
              className={isActive ? 'active' : ''}
              onClick={handleClick(t.id)}
            >
              {icon}
              <span>{t.label}</span>
            </button>
          );
        })}
      </div>
    </StyledWrapper>
  );
};

const StyledWrapper = styled.div`
  display: flex;
  justify-content: center;
  width: 100%;
  margin-bottom: 22px;

  .menu {
    width: 100%;
    max-width: ${(p) => (typeof p.$maxWidth === 'number' ? `${p.$maxWidth}px` : p.$maxWidth || '520px')};
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
    background: rgba(255, 255, 255, 0.94);
    border: 1px solid var(--color-line);
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.05);
    padding: 6px;
    border-radius: var(--radius-pill);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    z-index: 10;
  }

  .menu button {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    flex: 1 1 0;
    min-width: 74px;
    color: var(--color-muted);
    text-decoration: none;
    padding: 8px 12px;
    border-radius: var(--radius-pill);
    border: none;
    background: transparent;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: background-color var(--duration-fast), color var(--duration-fast), transform var(--duration-fast);
  }

  .menu button:hover {
    background-color: #f0f0f4;
    color: var(--color-ink);
    transform: translateY(-1px);
  }

  .menu button.active {
    background-color: var(--color-brand-wash);
    color: var(--color-brand);
    font-weight: 700;
    box-shadow: 0 2px 8px rgba(37, 47, 108, 0.08);
  }

  .menu button:active {
    transform: scale(0.97);
  }

  .menu svg {
    width: 20px;
    height: 20px;
    flex-shrink: 0;
    transition: transform var(--duration-fast);
  }

  .menu button:hover svg {
    transform: scale(1.08);
  }

  .menu span {
    font-size: 12px;
    font-weight: 600;
    line-height: 1;
    margin-top: 4px;
    white-space: nowrap;
    letter-spacing: -0.01em;
  }
`;

export default Card;