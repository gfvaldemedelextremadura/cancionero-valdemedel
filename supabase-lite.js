/*
  Supabase Lite para Cancionero Valdemedel
  Cliente local sin dependencias externas. Usa las APIs oficiales de Auth y REST
  de Supabase y mantiene las actuaciones actualizadas mediante comprobaciones
  periódicas. La clave publishable es pública; la seguridad la controlan las RLS.
*/
(function (global) {
  'use strict';

  const SESSION_KEY = 'valdemedel_supabase_session_v1';

  function makeError(message, status, details) {
    const error = new Error(message || 'Error de Supabase');
    if (status) error.status = status;
    if (details) error.details = details;
    return error;
  }

  async function parseResponse(response) {
    if (response.status === 204) return null;
    const text = await response.text();
    if (!text) return null;
    try { return JSON.parse(text); } catch (_) { return text; }
  }

  function createClient(projectUrl, publishableKey, options) {
    const baseUrl = String(projectUrl || '').replace(/\/+$/, '');
    const apiKey = String(publishableKey || '').trim();
    const listeners = new Set();
    let session = readSession();

    if (!/^https:\/\/.+\.supabase\.co$/i.test(baseUrl)) {
      throw makeError('La URL del proyecto Supabase no es válida.');
    }
    if (!apiKey.startsWith('sb_publishable_') && apiKey.split('.').length !== 3) {
      throw makeError('La Publishable key de Supabase no es válida.');
    }

    function readSession() {
      try {
        const raw = localStorage.getItem(SESSION_KEY);
        return raw ? JSON.parse(raw) : null;
      } catch (_) { return null; }
    }

    function writeSession(next) {
      session = next || null;
      try {
        if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session));
        else localStorage.removeItem(SESSION_KEY);
      } catch (_) {}
    }

    function emit(event, nextSession) {
      listeners.forEach((callback) => {
        try { callback(event, nextSession || null); } catch (error) { console.error(error); }
      });
    }

    function normalizeSession(payload) {
      if (!payload || !payload.access_token) return null;
      return {
        access_token: payload.access_token,
        refresh_token: payload.refresh_token || session?.refresh_token || '',
        token_type: payload.token_type || 'bearer',
        expires_in: Number(payload.expires_in || 3600),
        expires_at: Number(payload.expires_at || Math.floor(Date.now() / 1000) + Number(payload.expires_in || 3600)),
        user: payload.user || session?.user || null
      };
    }

    async function authRequest(path, body, accessToken) {
      const headers = {
        apikey: apiKey,
        'Content-Type': 'application/json'
      };
      if (accessToken) headers.Authorization = 'Bearer ' + accessToken;
      let response;
      try {
        response = await fetch(baseUrl + path, {
          method: 'POST',
          headers,
          body: body === undefined ? undefined : JSON.stringify(body),
          cache: 'no-store'
        });
      } catch (error) {
        throw makeError('No se ha podido conectar con Supabase. Comprueba la conexión a Internet.', 0, error);
      }
      const payload = await parseResponse(response);
      if (!response.ok) {
        const message = payload?.msg || payload?.message || payload?.error_description || payload?.error || ('Error HTTP ' + response.status);
        throw makeError(message, response.status, payload);
      }
      return payload;
    }

    async function refreshSessionIfNeeded() {
      if (!session) return null;
      const expiresAt = Number(session.expires_at || 0);
      if (!expiresAt || expiresAt > Math.floor(Date.now() / 1000) + 60) return session;
      if (!session.refresh_token) {
        writeSession(null);
        emit('SIGNED_OUT', null);
        return null;
      }
      try {
        const payload = await authRequest('/auth/v1/token?grant_type=refresh_token', { refresh_token: session.refresh_token });
        const refreshed = normalizeSession(payload);
        writeSession(refreshed);
        emit('TOKEN_REFRESHED', refreshed);
        return refreshed;
      } catch (error) {
        console.warn('No se pudo renovar la sesión de Supabase', error);
        writeSession(null);
        emit('SIGNED_OUT', null);
        return null;
      }
    }

    async function request(method, table, query, body, prefer) {
      const activeSession = await refreshSessionIfNeeded();
      const headers = {
        apikey: apiKey,
        Authorization: 'Bearer ' + (activeSession?.access_token || apiKey)
      };
      if (body !== undefined) headers['Content-Type'] = 'application/json';
      if (prefer) headers.Prefer = prefer;
      if (method === 'GET') query.set('_vmts', String(Date.now()));
      const queryString = query.toString();
      const url = baseUrl + '/rest/v1/' + encodeURIComponent(table) + (queryString ? '?' + queryString : '');
      let response;
      try {
        response = await fetch(url, {
          method,
          headers,
          body: body === undefined ? undefined : JSON.stringify(body),
          cache: 'no-store'
        });
      } catch (error) {
        throw makeError('No se ha podido conectar con la base de datos compartida.', 0, error);
      }
      const payload = await parseResponse(response);
      if (!response.ok) {
        const message = payload?.message || payload?.hint || payload?.details || payload?.code || ('Error HTTP ' + response.status);
        throw makeError(message, response.status, payload);
      }
      return payload;
    }

    class QueryBuilder {
      constructor(table) {
        this.table = table;
        this.operation = 'select';
        this.columns = '*';
        this.values = undefined;
        this.onConflict = '';
        this.filters = [];
        this.orders = [];
        this.maxRows = null;
        this.wantSingle = false;
        this.returning = false;
      }
      select(columns) {
        this.columns = columns || '*';
        if (this.operation !== 'select') this.returning = true;
        return this;
      }
      order(column, options) {
        const direction = options?.ascending === false ? 'desc' : 'asc';
        const nulls = options?.nullsFirst === true ? '.nullsfirst' : options?.nullsFirst === false ? '.nullslast' : '';
        this.orders.push(String(column) + '.' + direction + nulls);
        return this;
      }
      limit(value) { this.maxRows = Number(value); return this; }
      upsert(values, options) {
        this.operation = 'upsert';
        this.values = values;
        this.onConflict = options?.onConflict || '';
        return this;
      }
      delete() { this.operation = 'delete'; return this; }
      eq(column, value) { this.filters.push([column, value]); return this; }
      single() { this.wantSingle = true; return this; }
      then(resolve, reject) { return this.execute().then(resolve, reject); }
      async execute() {
        try {
          const query = new URLSearchParams();
          this.filters.forEach(([column, value]) => query.append(column, 'eq.' + String(value)));
          if (this.operation === 'select') {
            query.set('select', this.columns || '*');
            if (this.orders.length) query.set('order', this.orders.join(','));
            if (Number.isFinite(this.maxRows)) query.set('limit', String(this.maxRows));
            let data = await request('GET', this.table, query);
            if (this.wantSingle) {
              if (!Array.isArray(data) || data.length !== 1) throw makeError('Supabase no devolvió exactamente un registro.');
              data = data[0];
            }
            return { data, error: null };
          }
          if (this.operation === 'upsert') {
            if (this.onConflict) query.set('on_conflict', this.onConflict);
            if (this.returning) query.set('select', this.columns || '*');
            let data = await request(
              'POST',
              this.table,
              query,
              this.values,
              'resolution=merge-duplicates,' + (this.returning ? 'return=representation' : 'return=minimal')
            );
            if (this.wantSingle) {
              if (!Array.isArray(data) || data.length !== 1) throw makeError('Supabase no confirmó el registro guardado.');
              data = data[0];
            }
            return { data, error: null };
          }
          if (this.operation === 'delete') {
            const data = await request('DELETE', this.table, query, undefined, 'return=minimal');
            return { data, error: null };
          }
          throw makeError('Operación no compatible.');
        } catch (error) {
          return { data: null, error };
        }
      }
    }

    const auth = {
      async getSession() {
        const current = await refreshSessionIfNeeded();
        return { data: { session: current }, error: null };
      },
      async signInWithPassword(credentials) {
        try {
          const payload = await authRequest('/auth/v1/token?grant_type=password', {
            email: String(credentials?.email || '').trim(),
            password: String(credentials?.password || '')
          });
          const next = normalizeSession(payload);
          writeSession(next);
          emit('SIGNED_IN', next);
          return { data: { session: next, user: next?.user || null }, error: null };
        } catch (error) {
          return { data: { session: null, user: null }, error };
        }
      },
      async signOut() {
        const current = session;
        if (current?.access_token) {
          try { await authRequest('/auth/v1/logout', undefined, current.access_token); } catch (_) {}
        }
        writeSession(null);
        emit('SIGNED_OUT', null);
        return { error: null };
      },
      onAuthStateChange(callback) {
        listeners.add(callback);
        setTimeout(() => callback('INITIAL_SESSION', session), 0);
        return { data: { subscription: { unsubscribe: () => listeners.delete(callback) } } };
      }
    };

    function channel(name) {
      let callback = null;
      let timer = null;
      let visibilityHandler = null;
      let onlineHandler = null;
      const api = {
        on(event, filter, handler) { callback = handler; return api; },
        subscribe(statusCallback) {
          const notify = () => { if (callback) callback({ eventType: 'POLL' }); };
          timer = setInterval(notify, 5000);
          visibilityHandler = () => { if (document.visibilityState === 'visible') notify(); };
          onlineHandler = notify;
          document.addEventListener('visibilitychange', visibilityHandler);
          global.addEventListener('online', onlineHandler);
          if (typeof statusCallback === 'function') setTimeout(() => statusCallback('SUBSCRIBED'), 0);
          return api;
        },
        unsubscribe() {
          if (timer) clearInterval(timer);
          if (visibilityHandler) document.removeEventListener('visibilitychange', visibilityHandler);
          if (onlineHandler) global.removeEventListener('online', onlineHandler);
        }
      };
      return api;
    }

    return {
      auth,
      from(table) { return new QueryBuilder(table); },
      channel,
      removeChannel(ch) { if (ch?.unsubscribe) ch.unsubscribe(); }
    };
  }

  global.supabase = { createClient };
})(window);
