import { useEffect, useState } from "react";

export default function useApiData(loader, dependencies = []) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");

    Promise.resolve()
      .then(loader)
      .then((result) => {
        if (active) setData(result);
      })
      .catch((err) => {
        if (active) setError(err?.message || "Unable to load data from the backend.");
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
    // The caller controls dependencies intentionally.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, dependencies);

  return { data, loading, error };
}

export function LoadingState({ message = "Loading data…" }) {
  return <div className="empty-state">{message}</div>;
}

export function ErrorState({ message }) {
  return <div className="empty-state">{message}</div>;
}
