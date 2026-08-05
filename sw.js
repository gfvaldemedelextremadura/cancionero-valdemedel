const C='valdemedel-v4.53';
const PDF_CACHE='valdemedel-v4.53-pdfs';
const A=['./','./index.html','./styles.css?v=4.53','./supabase-config.js?v=4.53','./supabase-lite.js?v=4.53','./app.js?v=4.53','./manifest.webmanifest','./logo-burdeos.png','./logo-blanco.png','./logo-texto.png','./actuacion-infantil.jpeg','./romeria.jpeg','./musicos-historicos.jpeg','./grupo.jpeg','./musicos-escenario.jpeg','./festival.jpeg','./tamborilero.jpeg','./baile.jpeg'];
self.addEventListener('install',event=>{self.skipWaiting();event.waitUntil(caches.open(C).then(cache=>cache.addAll(A)))});
self.addEventListener('activate',event=>event.waitUntil(Promise.all([
 self.clients.claim(),
 caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==C&&key!==PDF_CACHE).map(key=>caches.delete(key))))
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
