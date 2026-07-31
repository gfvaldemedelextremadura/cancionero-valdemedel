const C='valdemedel-v4-5';
const A=['./','./index.html','./styles.css?v=4.5','./app.js?v=4.5','./logo-burdeos.png','./logo-blanco.png','./logo-texto.png','./actuacion-infantil.jpeg','./romeria.jpeg','./musicos-historicos.jpeg','./grupo.jpeg','./musicos-escenario.jpeg','./festival.jpeg','./tamborilero.jpeg','./baile.jpeg'];
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(C).then(c=>c.addAll(A)))});
self.addEventListener('activate',e=>e.waitUntil(Promise.all([self.clients.claim(),caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x))))])));
self.addEventListener('fetch',e=>{
 const r=e.request;
 if(r.method!=='GET')return;
 const u=new URL(r.url);
 if(u.origin===location.origin&&(r.mode==='navigate'||/\.(?:js|css)$/.test(u.pathname))){
  e.respondWith(fetch(r).then(resp=>{const copy=resp.clone();caches.open(C).then(c=>c.put(r,copy));return resp}).catch(()=>caches.match(r).then(x=>x||caches.match('./index.html'))));
  return;
 }
 e.respondWith(caches.match(r).then(x=>x||fetch(r).then(resp=>{const copy=resp.clone();caches.open(C).then(c=>c.put(r,copy));return resp})));
});
