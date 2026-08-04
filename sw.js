const C='valdemedel-v4.50';
const PDF_CACHE='valdemedel-v4.50-pdfs';
const A=['./','./index.html','./styles.css?v=4.49','./supabase-config.js?v=4.49','./supabase-lite.js?v=4.49','./app.js?v=4.49','./manifest.webmanifest','./logo-burdeos.png','./logo-blanco.png','./logo-texto.png','./actuacion-infantil.jpeg','./romeria.jpeg','./musicos-historicos.jpeg','./grupo.jpeg','./musicos-escenario.jpeg','./festival.jpeg','./tamborilero.jpeg','./baile.jpeg'];
function timedFetch(request,ms=6000){const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),ms);return fetch(request,{signal:controller.signal}).finally(()=>clearTimeout(timer))}
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(C).then(c=>c.addAll(A)))});
self.addEventListener('activate',e=>e.waitUntil(Promise.all([self.clients.claim(),caches.keys().then(k=>Promise.all(k.filter(x=>x!==C&&x!==PDF_CACHE).map(x=>caches.delete(x))))])));
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET')return;const u=new URL(r.url);
 if(u.origin!==self.location.origin){if(u.pathname.includes('/storage/v1/object/public/dance-pdfs/')){e.respondWith(caches.open(PDF_CACHE).then(async c=>{try{const resp=await timedFetch(r,8000);if(resp.ok)c.put(r,resp.clone());return resp}catch{return (await c.match(r))||Response.error()}}));}else e.respondWith(timedFetch(r,9000));return;}
 if(r.mode==='navigate'){e.respondWith(timedFetch(new Request(r,{cache:'no-store'}),7000).then(resp=>{const copy=resp.clone();caches.open(C).then(c=>c.put('./index.html',copy));return resp}).catch(()=>caches.match('./index.html')));return;}
 if(/\.(?:js|css)$/.test(u.pathname)){e.respondWith(timedFetch(r,5000).then(resp=>{const copy=resp.clone();caches.open(C).then(c=>c.put(r,copy));return resp}).catch(()=>caches.match(r)));return;}
 e.respondWith(caches.match(r).then(x=>x||timedFetch(r,7000).then(resp=>{const copy=resp.clone();caches.open(C).then(c=>c.put(r,copy));return resp})));});
