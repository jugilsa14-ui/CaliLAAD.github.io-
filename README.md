# CALI.LAAD

Web de calistenia de fuerza basada en el método LAD: plan por mesociclos, registro de sesiones, carga (LAD-Au e INOL), volumen por progresión, evolución, simulador de torques y modo entrenador con carpeta de deportistas.

## Archivos

- `index.html`: la web completa, un solo archivo.
- `manifest.webmanifest`, `sw.js` e iconos (`icon-*.png`, `apple-touch-icon.png`, `favicon-32.png`): permiten instalar la web como app en el móvil o el ordenador y abrirla sin conexión.
- `supabase_setup.sql`: base de datos (cuentas, sesiones, pago, ajustes). Se pega entera en Supabase → SQL Editor → Run.
- `supabase/functions/pago/index.ts`: recibe el aviso de pago y desbloquea la cuenta.
- `privacidad.html`, `condiciones.html`, `aviso-legal.html`: páginas legales (rellenar los huecos marcados).

## Cómo funciona el acceso

1. Al entrar, cada persona crea su cuenta con su correo y una contraseña (y confirma el correo).
2. Puede guardar **5 sesiones gratis** por cuenta.
3. Al llegar a las 5 sesiones, la web entera queda bloqueada hasta el **pago único de 4,99 €**. Mientras tanto puede descargar sus datos, salir o borrar la cuenta.
   El límite de guardado lo impone la base de datos; el bloqueo del resto de la web lo hace la página.
4. Sus sesiones, su plan y sus deportistas se guardan en su cuenta: los ve en cualquier dispositivo.

## Puesta en marcha (una vez)

1. **Supabase** (supabase.com, plan gratuito): crea un proyecto.
   - SQL Editor → pega `supabase_setup.sql` → Run.
   - Authentication → URL Configuration → Site URL: la dirección de la web.
   - Project Settings → API: copia la *Project URL* y la clave pública (*anon* / *publishable*). **Nunca** la *service_role*.
2. **Cobro** (Stripe o Lemon Squeezy): crea un producto de 4,99 € con pago único y su enlace de pago (Stripe: *Payment Link*; Lemon Squeezy: *checkout*). Como página de éxito, pon la web con `?pagado=1` al final.
3. **Función de pago**: despliega `supabase/functions/pago` (Supabase → Edge Functions) y guarda el secreto del webhook de la plataforma de cobro en Edge Functions → Secrets (`STRIPE_WEBHOOK_SECRET` o `LEMONSQUEEZY_WEBHOOK_SECRET`). En la plataforma de cobro, crea el webhook hacia la URL de la función.
4. En `index.html`, rellena `SB_CONF` (URL y clave pública) y `PAY_CONF` (enlace de pago). Sin ellos la web funciona en «modo prueba», con los datos solo en el navegador.
5. Para tu propia cuenta de autor, usa la consulta del final de `supabase_setup.sql` para marcarla como pagada.

## Publicar una versión nueva

GitHub Pages publica la rama principal. Al cambiar la web, sube también el número de versión `V` de `sw.js` para que los móviles con la app instalada reciban la nueva.
