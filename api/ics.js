// Cancionero Valdemedel · v4.68
// Genera un archivo de calendario (.ics) a partir de los datos de la URL para que
// iPhone/iPad (Safari y app instalada) lo abran con «Añadir al calendario».
// Solo recibe título, fecha, hora y lugar; no guarda nada.
// Parámetro: d = JSON en base64url con [{k,t,d,h,p}] (tipo, título, fecha, hora, lugar).

const KIND = { rehearsal: 'Ensayo', poll: 'Encuesta de actuación', performance: 'Actuación', task: 'Tarea' };

function text(s, max) {
  return String(s == null ? '' : s).slice(0, max)
    .replace(/\\/g, '\\\\').replace(/\r?\n/g, '\\n').replace(/,/g, '\\,').replace(/;/g, '\\;');
}
function fold(line) {
  const out = []; let rest = line;
  while (Buffer.byteLength(rest, 'utf8') > 72) {
    let cut = 70; while (Buffer.byteLength(rest.slice(0, cut), 'utf8') > 72) cut--;
    out.push(rest.slice(0, cut)); rest = ' ' + rest.slice(cut);
  }
  out.push(rest); return out.join('\r\n');
}
const pad = n => String(n).padStart(2, '0');
function stamp(d) { return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate()) + 'T' + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + pad(d.getUTCSeconds()) + 'Z'; }
function local(y, m, d, h, mi) { return '' + y + pad(m) + pad(d) + 'T' + pad(h) + pad(mi) + '00'; }

function vevent(e, i, now) {
  const [y, m, d] = e.d.split('-').map(Number);
  const lines = ['BEGIN:VEVENT', 'UID:' + (e.k || 'evento') + '-' + e.d + '-' + i + '-' + Math.abs(hash(e.t)) + '@cancionero-valdemedel', 'DTSTAMP:' + now];
  if (e.h) {
    const [h, mi] = e.h.split(':').map(Number);
    const end = new Date(Date.UTC(y, m - 1, d, h + 2, mi));
    lines.push('DTSTART:' + local(y, m, d, h, mi), 'DTEND:' + local(end.getUTCFullYear(), end.getUTCMonth() + 1, end.getUTCDate(), end.getUTCHours(), end.getUTCMinutes()));
  } else {
    const next = new Date(Date.UTC(y, m - 1, d + 1));
    lines.push('DTSTART;VALUE=DATE:' + y + pad(m) + pad(d), 'DTEND;VALUE=DATE:' + next.getUTCFullYear() + pad(next.getUTCMonth() + 1) + pad(next.getUTCDate()));
  }
  lines.push('SUMMARY:' + text((KIND[e.k] ? KIND[e.k] + ' · ' : '') + e.t, 200));
  if (e.p) lines.push('LOCATION:' + text(e.p, 200));
  lines.push('DESCRIPTION:' + text('Grupo Folklórico Valdemedel · https://cancionero-valdemedel.vercel.app', 200));
  if (e.h) lines.push('BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:' + text(e.t, 200), 'TRIGGER:-PT2H', 'END:VALARM');
  lines.push('END:VEVENT');
  return lines.map(fold).join('\r\n');
}
function hash(s) { let h = 0; for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) | 0; return h; }

module.exports = (req, res) => {
  let events = [];
  try {
    const raw = String((req.query && req.query.d) || '');
    const parsed = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
    events = (Array.isArray(parsed) ? parsed : []).slice(0, 60).map(e => ({
      k: String(e && e.k || ''), t: String(e && e.t || 'Evento').trim() || 'Evento',
      d: String(e && e.d || ''), h: String(e && e.h || ''), p: String(e && e.p || '')
    })).filter(e => /^\d{4}-\d{2}-\d{2}$/.test(e.d)).map(e => ({ ...e, h: /^\d{2}:\d{2}$/.test(e.h) ? e.h : '' }));
  } catch (_) { events = []; }
  if (!events.length) {
    res.statusCode = 400;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    return res.end('No hay ninguna fecha válida para añadir al calendario.');
  }
  const now = stamp(new Date());
  const body = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Grupo Folklorico Valdemedel//Cancionero//ES', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'X-WR-CALNAME:Grupo Folklórico Valdemedel', ...events.map((e, i) => vevent(e, i, now)), 'END:VCALENDAR'].join('\r\n') + '\r\n';
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
  res.setHeader('Content-Disposition', 'inline; filename="valdemedel.ics"');
  res.setHeader('Cache-Control', 'no-store');
  res.end(body);
};
