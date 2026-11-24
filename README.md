# CALI.LAAD

Web de calistenia de fuerza basada en el método LAD: plan por mesociclos, registro de sesiones, carga (LAD-Au e INOL), volumen por progresión, evolución, simulador de torques y modo entrenador con carpeta de deportistas.

## Archivos

- `index.html`: la web completa, un solo archivo.
- `manifest.webmanifest`, `sw.js` e iconos (`icon-*.png`, `apple-touch-icon.png`, `favicon-32.png`): permiten instalar la web como app en el móvil o el ordenador y abrirla sin conexión.
- `supabase_setup.sql`: base de datos (cuentas, sesiones, pago, ajustes). Se pega entera en Supabase → SQL Editor → Run.
- `supabase/functions/pago/index.ts`: recibe los avisos de Stripe (alta, renovación y baja de las suscripciones).
- `privacidad.html`, `condiciones.html` (condiciones de uso y contratación, con aviso de salud y cláusula de encargado del tratamiento para entrenadores), `aviso-legal.html`: páginas legales (rellenar los huecos marcados).

## Cómo funciona el acceso

1. Al entrar, cada persona crea su cuenta con su correo y una contraseña (y confirma el correo). Acepta las condiciones de uso (con el aviso de salud) y la política de privacidad.
2. Puede usar toda la web gratis hasta guardar **5 sesiones**.
3. Después, la web queda bloqueada hasta suscribirse: **19,99 € al año**, renovación automática, cancelable cuando quiera (conserva el acceso hasta el final del año pagado).
4. En el modo entrenador, cada deportista cuesta **4,99 € al año**. Para añadir un deportista, el entrenador confirma que tiene su permiso.
5. Si la suscripción termina, los datos se conservan; la persona puede descargarlos o borrar la cuenta desde la pantalla de pago.
6. Desde Evolución se descargan o envían **informes** del periodo (PDF, archivo o «Enviar…» en el móvil).

## Puesta en marcha (una vez)

1. **Supabase** (supabase.com): crea un proyecto en una **región de la UE**.
   - SQL Editor → pega `supabase_setup.sql` entero → Run.
   - Authentication → URL Configuration → Site URL: la dirección de la web.
   - Project Settings → API: copia la *Project URL* y la clave pública (*anon* / *publishable*). **Nunca** la *service_role*.
2. **Stripe** (stripe.com): crea dos productos con **precio recurrente anual** y su *Payment Link*:
   - «CALI.LAAD · acceso» (19,99 €/año) y «CALI.LAAD · deportista» (4,99 €/año).
   - En cada enlace: página de confirmación → la web con `?pagado=1` al final.
   - Configuración → Facturación → **Portal de clientes**: actívalo (permitir cancelar) y copia su enlace de inicio de sesión.
   - Configuración → Facturación → Suscripciones y correos: activa los **recordatorios de renovación** y los reintentos de cobro.
3. **Función de pago**: despliega `supabase/functions/pago` (Supabase → Edge Functions) con la verificación JWT desactivada. En Stripe → Desarrolladores → Webhooks, crea uno hacia la URL de la función con los eventos `checkout.session.completed`, `invoice.paid` y `customer.subscription.deleted`, y guarda su secreto (`whsec_…`) en Supabase → Edge Functions → Secrets como `STRIPE_WEBHOOK_SECRET`.
4. En `index.html`, rellena `SB_CONF` (URL y clave pública) y `PAY_CONF` (`url`: enlace de 19,99 €; `athUrl`: enlace de 4,99 €; `portal`: enlace del portal de clientes). Sin ellos la web funciona en «modo prueba», con los datos solo en el navegador.
5. Completa los datos en amarillo de `aviso-legal.html`, `privacidad.html` y `condiciones.html` (nombre, NIF, dirección y correo).
6. Para tu propia cuenta de autor, usa la consulta del final de la parte 3 de `supabase_setup.sql` para marcarla como pagada.

## Publicar una versión nueva

GitHub Pages publica la rama principal. Al cambiar la web, sube también el número de versión `V` de `sw.js` para que los móviles con la app instalada reciban la nueva.
