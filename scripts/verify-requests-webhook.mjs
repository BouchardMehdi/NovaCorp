import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { prepare, publicUrl } from "./ngrok-tools.mjs";

try {
  const token = await prepare();
  const base = process.argv.includes("--public") ? await publicUrl() : "http://127.0.0.1:5678";
  // Données synthétiques : cet identifiant ne correspond à aucune demande en base.
  const record = { id: randomUUID(), status: "draft" };
  const body = JSON.stringify({ type: "INSERT", schema: "public", table: "requests", record, old_record: null });
  const headers = { "Content-Type": "application/json", "ngrok-skip-browser-warning": "1" };
  const endpoint = base + "/webhook/novacorp-requests";
  const denied = await fetch(endpoint, { method: "POST", headers, body, signal: AbortSignal.timeout(15000) });
  assert.ok([401, 403].includes(denied.status), "Le webhook doit refuser un appel sans authentification.");
  const response = await fetch(endpoint, {
    method: "POST", headers: { ...headers, "X-NovaCorp-Webhook-Token": token }, body,
    signal: AbortSignal.timeout(15000),
  });
  assert.equal(response.status, 200, "Le webhook authentifié doit répondre 200.");
  assert.deepEqual(await response.json(), {
    received: true, event: "INSERT", table: "requests", request_id: record.id, status: "draft", business_processing: false,
  });
  console.log("OK : réception authentifiée, appel anonyme refusé, brouillon synthétique sans action RH.");
  console.log("Aucune demande, validation, réservation ou notification modifiée dans Supabase local.");
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
