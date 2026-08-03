# Cancionero Valdemedel v4.9

Aplicación web/PWA del Grupo Folklórico Valdemedel.

## Novedad: actuaciones compartidas

Las actuaciones dejan de depender únicamente del navegador. Con Supabase configurado:

- cualquier visitante puede consultar las actuaciones publicadas;
- solo el administrador autenticado puede crear, editar o eliminar;
- se comparten el nombre, fecha, lugar, orden de canciones y anotaciones;
- los dispositivos abiertos reciben los cambios mediante Realtime;
- las actuaciones antiguas guardadas en el navegador se conservan y el administrador puede publicarlas desde **Actuaciones** o **Datos**.

## Configuración necesaria

### 1. Crear el proyecto de Supabase

Crea un proyecto y espera a que termine la preparación.

### 2. Crear el administrador

En **Authentication > Users**, crea un usuario con correo y contraseña. Desactiva el registro público si no lo necesitas.

### 3. Preparar la base de datos

Abre `supabase-setup.sql`, sustituye todas las apariciones de `TU_CORREO_ADMINISTRADOR` por el correo real y ejecuta el contenido en **SQL Editor**.

### 4. Conectar la app

Edita `supabase-config.js` y completa:

```js
window.VALDEMEDEL_CLOUD = {
  url: 'https://TU-PROYECTO.supabase.co',
  publishableKey: 'TU_CLAVE_PUBLICABLE',
  adminEmail: 'correo@ejemplo.com'
};
```

Usa la clave **Publishable** o **anon**. No uses nunca la clave `service_role` en la aplicación.

### 5. Publicar en GitHub/Vercel

Sube todos los archivos a la raíz del repositorio. Vercel desplegará la aplicación estática sin comando de compilación.

## Uso

- Los usuarios normales abren **Actuaciones** y ven la información compartida.
- El administrador pulsa el candado e inicia sesión con el usuario de Supabase.
- Al guardar o modificar una actuación, se publica directamente para todos.
- Si existen actuaciones de versiones anteriores, aparecerá **Publicar ahora**.

## Archivos principales

- `index.html`
- `app.js`
- `styles.css`
- `supabase-config.js`
- `supabase-setup.sql`
- `sw.js`
- `vercel.json`


## Versión 4.11

Se corrige el modo actuación para canciones largas. La aplicación detecta ahora el contenido oculto dentro de cada columna y activa automáticamente el desplazamiento, de modo que Coplillas de Pique y cualquier otra letra extensa pueden recorrerse completas en ordenador, móvil y tableta.

## CONFIGURADO CON SUPABASE

Este paquete ya incluye la URL del proyecto, la Publishable key y el correo administrador de Valdemedel. Antes de publicar, ejecuta `supabase-setup.sql` una sola vez en el SQL Editor de Supabase y crea/confirma el usuario administrador en Authentication > Users.


## Cambios v4.11
- Supabase confirma cada alta o modificación antes de mostrar el mensaje de éxito.
- Las actuaciones antiguas del dispositivo se ofrecen para publicación al iniciar como administrador.
- Cada actuación compartida muestra la etiqueta «☁ Compartida».
- Botón «Comprobar conexión» con recuento de actuaciones visibles.
- Si falla la publicación, el repertorio y las anotaciones permanecen abiertos para no perder cambios.


## Versión 4.14
- Botón global ↻ para actualizar actuaciones y comprobar una versión nueva de la app.
- Actualización automática al volver a la app, recuperar conexión o enfocar la ventana.
- Comprobación periódica de actuaciones cada 30 segundos mientras la app está visible.

## Versión 4.15
- Corrige el error `failed to parse filter (...)` causado por un parámetro de caché incompatible con PostgREST.
- Añade copia de actuaciones para uso sin conexión.
- Las actuaciones descargadas pueden abrirse y usarse en modo actuación sin Internet.

## v4.16
- Zona de bailarines en cada actuación, con lista de bailes y PDF adjunto por el administrador.
- Afinador cromático integrado mediante el micrófono del dispositivo.
- Ejecuta de nuevo `supabase-setup.sql` para crear las columnas y el bucket `dance-pdfs`.


## v4.17
- El apartado Bailarines usa automáticamente la misma lista y el mismo orden de canciones de la actuación.
- Se elimina el campo manual de lista de bailes para evitar duplicidades.
- El PDF para bailarines se mantiene como adjunto independiente.
