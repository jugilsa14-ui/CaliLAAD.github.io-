// CALI.LAAD · función de pagos (Supabase Edge Function «pago»)
// Recibe el aviso de la plataforma de cobro cuando alguien paga y marca su cuenta como pagada.
// Funciona con Lemon Squeezy o con Stripe; solo hay que poner el secreto de la que uses.
// Secretos (Supabase → Edge Functions → Secrets), NUNCA en la web ni en el chat:
//   LEMONSQUEEZY_WEBHOOK_SECRET  (si cobras con Lemon Squeezy)
//   STRIPE_WEBHOOK_SECRET        (si cobras con Stripe, empieza por whsec_)
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los pone Supabase solo dentro de la función.
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

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Solo POST", { status: 405 });
  const raw = await req.text();
  let userId = "", pedido = "", plataforma = "", pagado = false;

  const ls = req.headers.get("x-signature");
  const st = req.headers.get("stripe-signature");
  if (ls) {
    const secret = Deno.env.get("LEMONSQUEEZY_WEBHOOK_SECRET") ?? "";
    if (!secret || !same(await hmacHex(secret, raw), ls)) return new Response("Firma no válida", { status: 401 });
    const ev = JSON.parse(raw);
    plataforma = "lemonsqueezy";
    if (ev?.meta?.event_name === "order_created" && ev?.data?.attributes?.status === "paid") {
      userId = ev?.meta?.custom_data?.user_id ?? ""; pedido = String(ev?.data?.id ?? ""); pagado = true;
    }
    if (ev?.meta?.event_name === "order_refunded") { userId = ev?.meta?.custom_data?.user_id ?? ""; pedido = String(ev?.data?.id ?? ""); pagado = false; }
  } else if (st) {
    const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
    const parts = Object.fromEntries(st.split(",").map((p) => p.split("=") as [string, string]));
    const t = parts["t"], v1 = parts["v1"];
    if (!secret || !t || !v1 || !same(await hmacHex(secret, `${t}.${raw}`), v1)) return new Response("Firma no válida", { status: 401 });
    if (Math.abs(Date.now() / 1000 - Number(t)) > 300) return new Response("Aviso caducado", { status: 401 });
    const ev = JSON.parse(raw);
    plataforma = "stripe";
    if (ev.type === "checkout.session.completed" && ev.data?.object?.payment_status === "paid") {
      userId = ev.data.object.client_reference_id ?? ""; pedido = ev.data.object.id ?? ""; pagado = true;
    }
    if (ev.type === "charge.refunded") { userId = ev.data?.object?.metadata?.user_id ?? ""; pedido = ev.data?.object?.id ?? ""; pagado = false; }
  } else {
    return new Response("Aviso sin firma", { status: 400 });
  }

  if (!/^[0-9a-f-]{36}$/i.test(userId)) return new Response("Sin cuenta asociada: revisar a mano", { status: 200 });
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await db.from("perfiles").upsert({
    user_id: userId, pagado, pagado_en: pagado ? new Date().toISOString() : null, plataforma, pedido,
  });
  if (error) return new Response("Error al guardar: " + error.message, { status: 500 });
  return new Response("ok", { status: 200 });
});
