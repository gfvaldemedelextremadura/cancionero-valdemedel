const C='valdemedel-v4-25';
const PDF_CACHE='valdemedel-v4-25-pdfs';
const A=['./','./index.html','./styles.css?v=4.25','./supabase-config.js?v=4.25','./supabase-lite.js?v=4.25','./app.js?v=4.25','./manifest.webmanifest','./logo-burdeos.png','./logo-blanco.png','./logo-texto.png','./actuacion-infantil.jpeg','./romeria.jpeg','./musicos-historicos.jpeg','./grupo.jpeg','./musicos-escenario.jpeg','./festival.jpeg','./tamborilero.jpeg','./baile.jpeg'];
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(C).then(c=>c.addAll(A)))});
self.addEventListener('activate',e=>e.waitUntil(Promise.all([self.clients.claim(),caches.keys().then(k=>Promise.all(k.filter(x=>x!==C&&x!==PDF_CACHE).map(x=>caches.delete(x))))])));
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET')return;const u=new URL(r.url);
 if(u.origin!==self.location.origin){if(u.pathname.includes('/storage/v1/object/public/dance-pdfs/')){e.respondWith(caches.open(PDF_CACHE).then(async c=>{try{const resp=await fetch(r);if(resp.ok)c.put(r,resp.clone());return resp}catch{return (await c.match(r))||Response.error()}}));}else e.respondWith(fetch(r));return;}
 if(r.mode==='navigate'){e.respondWith(fetch(r).then(resp=>{const copy=resp.clone();caches.open(C).then(c=>c.put('./index.html',copy));return resp}).catch(()=>caches.match('./index.html')));return;}
 if(/\.(?:js|css)$/.test(u.pathname)){e.respondWith(fetch(r).then(resp=>{const copy=resp.clone();caches.open(C).then(c=>c.put(r,copy));return resp}).catch(()=>caches.match(r)));return;}
 e.respondWith(caches.match(r).then(x=>x||fetch(r).then(resp=>{const copy=resp.clone();caches.open(C).then(c=>c.put(r,copy));return resp})));});
