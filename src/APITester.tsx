import { useState, useEffect } from "react";

export function APITester() {
  const [data, setData] = useState<{ message: string } | null>(null);

  useEffect(() => {
    fetch("/api/hello")
      .then((res) => res.json())
      .then((data) => setData(data));
  }, []);

  return (
    <div>
      <h2>API Tester</h2>
      {data ? <p>Message from API: {data.message}</p> : <p>Loading...</p>}
    </div>
  );
}
