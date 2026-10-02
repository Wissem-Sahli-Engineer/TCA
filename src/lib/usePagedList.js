import { useCallback, useEffect, useRef, useState } from "react";

// Loads a server-paged list (limit / offset, total in the X-Total-Count header)
// one page at a time instead of downloading everything.
//
//   const { items, total, loading, error, hasMore, loadMore, reload } =
//     usePagedList("/api/clients", { q: "ben", tab: "all" });
//
// The first page is re-fetched whenever `params` change; answers that arrive
// after a newer request was made are dropped, so a slow search can't overwrite a
// newer one. Pass `enabled: false` to wait.
export function usePagedList(path, params = {}, { pageSize = 25, enabled = true } = {}) {
  const [items, setItems] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState(false);
  const latest = useRef(0);
  const key = JSON.stringify(params);

  const fetchPage = useCallback(
    async (offset) => {
      const query = new URLSearchParams();
      Object.entries(JSON.parse(key)).forEach(([k, v]) => {
        if (v !== undefined && v !== null && v !== "") query.set(k, v);
      });
      query.set("limit", pageSize);
      query.set("offset", offset);
      const res = await fetch(`${path}?${query}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      return { data: Array.isArray(data) ? data : [], total: Number(res.headers.get("X-Total-Count") ?? data.length) };
    },
    [path, key, pageSize]
  );

  const reload = useCallback(async () => {
    const id = ++latest.current;
    setLoading(true);
    setError(false);
    try {
      const page = await fetchPage(0);
      if (id !== latest.current) return;
      setItems(page.data);
      setTotal(page.total);
    } catch {
      if (id === latest.current) {
        setItems([]);
        setTotal(0);
        setError(true);
      }
    } finally {
      if (id === latest.current) setLoading(false);
    }
  }, [fetchPage]);

  useEffect(() => {
    if (enabled) reload();
  }, [enabled, reload]);

  const loadMore = useCallback(async () => {
    if (loadingMore || items.length >= total) return;
    const id = latest.current;
    setLoadingMore(true);
    try {
      const page = await fetchPage(items.length);
      if (id !== latest.current) return;
      setItems((prev) => [...prev, ...page.data]);
      setTotal(page.total);
    } catch {
      if (id === latest.current) setError(true);
    } finally {
      setLoadingMore(false);
    }
  }, [fetchPage, items.length, total, loadingMore]);

  return { items, total, loading, loadingMore, error, hasMore: items.length < total, loadMore, reload };
}

// A value that follows `value` after it has stopped changing for `ms` (search boxes).
export function useDebounced(value, ms = 300) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(timer);
  }, [value, ms]);
  return debounced;
}
