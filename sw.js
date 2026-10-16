const C='valdemedel-v4.68';
// v4.61: nombre fijo para no perder los PDF guardados sin conexión al actualizar.
const PDF_CACHE='valdemedel-pdfs';
const A=['./','./index.html','./styles.css?v=4.68','./supabase-config.js?v=4.68','./supabase-lite.js?v=4.68','./app.js?v=4.68','./manifest.webmanifest','./logo-burdeos.png','./logo-blanco.png','./logo-texto.png','./actuacion-infantil.jpeg','./romeria.jpeg','./musicos-historicos.jpeg','./grupo.jpeg','./musicos-escenario.jpeg','./festival.jpeg','./tamborilero.jpeg','./baile.jpeg'];
self.addEventListener('install',event=>{self.skipWaiting();event.waitUntil(caches.open(C).then(cache=>cache.addAll(A)))});
async function movePdfCaches(keys){
 const target=await caches.open(PDF_CACHE);
 for(const key of keys.filter(k=>k!==PDF_CACHE&&k.endsWith('-pdfs'))){
  try{const old=await caches.open(key);for(const req of await old.keys()){const res=await old.match(req);if(res&&!(await target.match(req)))await target.put(req,res)}}catch(e){}
 }
}
self.addEventListener('activate',event=>event.waitUntil(Promise.all([
 self.clients.claim(),
 caches.keys().then(async keys=>{await movePdfCaches(keys);return Promise.all(keys.filter(key=>key!==C&&key!==PDF_CACHE).map(key=>caches.delete(key)))})
])));
self.addEventListener('fetch',event=>{
 const req=event.request;
 if(req.method!=='GET')return;
 const url=new URL(req.url);
 if(url.origin!==self.location.origin){
   if(url.pathname.includes('/storage/v1/object/public/dance-pdfs/')){
     event.respondWith(caches.open(PDF_CACHE).then(async cache=>{
       try{const response=await fetch(req);if(response.ok)cache.put(req,response.clone());return response}
       catch(error){return (await cache.match(req))||Response.error()}
     }));
   }
   return;
 }
 // v4.68: las funciones del servidor (/api/) nunca pasan por la caché.
 if(url.pathname.startsWith('/api/'))return;
 if(req.mode==='navigate'){
   event.respondWith(fetch(req).then(response=>{
     caches.open(C).then(cache=>cache.put('./index.html',response.clone()));
     return response;
   }).catch(()=>caches.match('./index.html')));
   return;
 }
 event.respondWith(caches.match(req).then(cached=>cached||fetch(req).then(response=>{
   if(response.ok)caches.open(C).then(cache=>cache.put(req,response.clone()));
   return response;
 })));
});
