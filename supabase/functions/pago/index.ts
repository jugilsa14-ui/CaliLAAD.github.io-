// CALI.LAAD · función de pagos (Supabase Edge Function «pago»)
// Recibe los avisos de Stripe y mantiene al día las suscripciones anuales:
//   - acceso: 19,99 €/año  → perfiles.pagado_hasta
//   - cada deportista del modo entrenador: 4,99 €/año → atletas_pagados.pagado_hasta
// En el enlace de pago, client_reference_id = <cuenta> (acceso) o <cuenta>__<deportista>.
// Secreto (Supabase → Edge Functions → Secrets), NUNCA en la web ni en el chat:
//   STRIPE_WEBHOOK_SECRET (empieza por whsec_)
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los pone Supabase solo dentro de la función.
// Eventos que hay que activar en el webhook de Stripe:
//   checkout.session.completed, invoice.paid, customer.subscription.deleted
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const enc = new TextEncoder();
async function hmacHex(secret: string, msg: string) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(msg));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function same(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
const GRACIA = 3 * 86400; // 3 días de margen tras la fecha de renovación, por si el cobro tarda
const iso = (sec: number) => new Date(sec * 1000).toISOString();

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Solo POST", { status: 405 });
  const raw = await req.text();
  const st = req.headers.get("stripe-signature");
  if (!st) return new Response("Aviso sin firma", { status: 400 });
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  const parts = Object.fromEntries(st.split(",").map((p) => p.split("=") as [string, string]));
  const t = parts["t"], v1 = parts["v1"];
  if (!secret || !t || !v1 || !same(await hmacHex(secret, `${t}.${raw}`), v1)) return new Response("Firma no válida", { status: 401 });
  if (Math.abs(Date.now() / 1000 - Number(t)) > 300) return new Response("Aviso caducado", { status: 401 });

  const ev = JSON.parse(raw), o = ev.data?.object ?? {};
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const fail = (e: { message: string } | null) => e ? new Response("Error al guardar: " + e.message, { status: 500 }) : null;

  // 1. Alta: alguien acaba de suscribirse (acceso o deportista)
  if (ev.type === "checkout.session.completed") {
    if (o.payment_status !== "paid" && o.status !== "complete") return new Response("ok", { status: 200 });
    const [userId, athId = ""] = String(o.client_reference_id ?? "").split("__");
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return new Response("Sin cuenta asociada: revisar a mano", { status: 200 });
    const sub = String(o.subscription ?? ""), hasta = iso(Date.now() / 1000 + 366 * 86400 + GRACIA); // provisional hasta el aviso de la factura
    if (athId) {
      if (!/^[a-z0-9]{1,40}$/i.test(athId)) return new Response("Deportista no válido: revisar a mano", { status: 200 });
      const r = await db.from("atletas_pagados").upsert({ user_id: userId, ath_id: athId, plataforma: "stripe", pedido: o.id, stripe_sub: sub, pagado_hasta: hasta });
      return fail(r.error) ?? new Response("ok", { status: 200 });
    }
    const r = await db.from("perfiles").upsert({ user_id: userId, pagado_en: new Date().toISOString(), plataforma: "stripe", pedido: o.id,
      stripe_customer: String(o.customer ?? ""), stripe_sub: sub, pagado_hasta: hasta });
    return fail(r.error) ?? new Response("ok", { status: 200 });
  }

  // 2. Renovación cobrada: se alarga hasta el final del periodo pagado
  if (ev.type === "invoice.paid") {
    const sub = String(o.subscription ?? o.parent?.subscription_details?.subscription ?? "");
    const fin = Math.max(0, ...((o.lines?.data ?? []) as { period?: { end?: number } }[]).map((l) => l.period?.end ?? 0));
    if (!sub || !fin) return new Response("ok", { status: 200 });
    const hasta = iso(fin + GRACIA);
    const a = await db.from("perfiles").update({ pagado_hasta: hasta }).eq("stripe_sub", sub);
    const b = await db.from("atletas_pagados").update({ pagado_hasta: hasta }).eq("stripe_sub", sub);
    return fail(a.error ?? b.error) ?? new Response("ok", { status: 200 });
  }

  // 3. Baja: la suscripción termina (cancelada al final del año o sin pagar)
  if (ev.type === "customer.subscription.deleted") {
    const sub = String(o.id ?? ""), ahora = new Date().toISOString();
    const a = await db.from("perfiles").update({ pagado_hasta: ahora }).eq("stripe_sub", sub);
    const b = await db.from("atletas_pagados").update({ pagado_hasta: ahora }).eq("stripe_sub", sub);
    return fail(a.error ?? b.error) ?? new Response("ok", { status: 200 });
  }

  return new Response("ok", { status: 200 });
});
