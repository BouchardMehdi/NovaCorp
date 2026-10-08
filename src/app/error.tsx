"use client";

export default function ErrorPage({ reset }: { reset: () => void }) {
  return <main className="error-page"><h1>Le service est momentanément indisponible.</h1><p>Réessayez dans quelques instants.</p><button className="button primary" onClick={() => reset()}>Réessayer</button></main>;
}
