// In-memory stand-in for the Supabase client, used only by browser tests and
// visual reviews. It never reaches the production bundle: index.html loads
// src/js/main.js, and only test fixtures load this module.
const clone = value => value === undefined ? undefined : structuredClone(value);

function matches(row, filters) {
  return filters.every(([op, key, value]) => {
    if (key.includes('.')) return true; // embedded resource filters are pre-joined
    const field = row[key];
    switch (op) {
      case 'eq': return field === value;
      case 'neq': return field !== value;
      case 'in': return Array.isArray(value) && value.includes(field);
      case 'is': return value === null ? field === null || field === undefined : field === value;
      case 'gte': return field >= value;
      case 'lte': return field <= value;
      case 'gt': return field > value;
      case 'lt': return field < value;
      case 'contains': return Array.isArray(field) && [].concat(value).every(v => field.includes(v));
      default: return true;
    }
  });
}

class Query {
  constructor(db, table) {
    this.db = db; this.table = table; this.filters = []; this.sorts = [];
    this.window = null; this.mode = 'select'; this.payload = null; this.singleMode = null; this.wantCount = false;
  }
  select(_columns, options = {}) { if (this.mode === 'select') this.mode = 'select'; this.wantCount = Boolean(options.count); return this; }
  insert(rows) { this.mode = 'insert'; this.payload = rows; return this; }
  update(patch) { this.mode = 'update'; this.payload = patch; return this; }
  upsert(rows) { this.mode = 'upsert'; this.payload = rows; return this; }
  delete() { this.mode = 'delete'; return this; }
  eq(k, v) { this.filters.push(['eq', k, v]); return this; }
  neq(k, v) { this.filters.push(['neq', k, v]); return this; }
  in(k, v) { this.filters.push(['in', k, v]); return this; }
  is(k, v) { this.filters.push(['is', k, v]); return this; }
  gte(k, v) { this.filters.push(['gte', k, v]); return this; }
  lte(k, v) { this.filters.push(['lte', k, v]); return this; }
  gt(k, v) { this.filters.push(['gt', k, v]); return this; }
  lt(k, v) { this.filters.push(['lt', k, v]); return this; }
  contains(k, v) { this.filters.push(['contains', k, v]); return this; }
  filter() { return this; }
  match(obj) { for (const [k, v] of Object.entries(obj)) this.eq(k, v); return this; }
  order(key, { ascending = true } = {}) { this.sorts.push([key, ascending]); return this; }
  limit(n) { this.window = [0, n - 1]; return this; }
  range(a, b) { this.window = [a, b]; return this; }
  maybeSingle() { this.singleMode = "maybe"; return this; }
  single() { this.singleMode = "one"; return this; }
  async run() {
    const state = this.db.state;
    if (state.delay) await new Promise(done => setTimeout(done, state.delay));
    if (state.failTables?.includes(this.table)) return { data: null, error: { message: 'Servizio non raggiungibile' } };
    state.calls.push({ table: this.table, mode: this.mode, filters: clone(this.filters), payload: clone(this.payload) });
    const rows = this.db.tables[this.table] ||= [];
    if (this.mode === 'insert' || this.mode === 'upsert') {
      const list = [].concat(this.payload).map(row => ({ id: crypto.randomUUID(), ...clone(row) }));
      rows.push(...list);
      return this.finish(list);
    }
    let selected = rows.filter(row => matches(row, this.filters));
    if (this.mode === 'update') { for (const row of selected) Object.assign(row, clone(this.payload)); return this.finish(selected); }
    if (this.mode === 'delete') { this.db.tables[this.table] = rows.filter(row => !selected.includes(row)); return this.finish(selected); }
    for (const [key, asc] of [...this.sorts].reverse()) {
      selected = [...selected].sort((a, b) => (a[key] > b[key] ? 1 : a[key] < b[key] ? -1 : 0) * (asc ? 1 : -1));
    }
    const count = selected.length;
    if (this.window) selected = selected.slice(this.window[0], this.window[1] + 1);
    return this.finish(selected, count);
  }
  finish(list, count = list.length) {
    if (this.singleMode) {
      if (this.singleMode === "one" && !list.length) return { data: null, error: { message: 'Nessuna riga trovata' } };
      return { data: clone(list[0] ?? null), error: null };
    }
    return { data: clone(list), error: null, count: this.wantCount ? count : null };
  }
  then(resolve, reject) { return this.run().then(resolve, reject); }
}

export function createMockClient({ tables = {}, rpc = {}, functions = {}, user = null, aal = 'aal2', state = {} } = {}) {
  const callbacks = [];
  const db = { tables: clone(tables), state: Object.assign({ calls: [], rpcCalls: [], delay: 0, user, aal }, state) };
  const emit = (event, session) => callbacks.forEach(fn => { try { fn(event, session); } catch (error) { console.error(error); } });
  const session = () => db.state.user ? { user: db.state.user, access_token: 'demo' } : null;
  const client = {
    db,
    auth: {
      onAuthStateChange(fn) { callbacks.push(fn); return { data: { subscription: { unsubscribe() {} } } }; },
      async getUser() { return { data: { user: clone(db.state.user) }, error: null }; },
      async getSession() { return { data: { session: clone(session()) }, error: null }; },
      async signInWithPassword({ email }) {
        db.state.user = db.state.loginUser || { id: 'demo-user', email };
        queueMicrotask(() => emit('SIGNED_IN', session()));
        return { data: { user: clone(db.state.user), session: clone(session()) }, error: null };
      },
      async signUp() { return { data: { user: null, session: null }, error: null }; },
      async signInWithOtp() { return { data: {}, error: null }; },
      async signInWithOAuth() { return { data: {}, error: { message: 'Accesso social non disponibile nella prova' } }; },
      async setSession() { return { data: { session: session() }, error: null }; },
      async signOut() { db.state.user = null; queueMicrotask(() => emit('SIGNED_OUT', null)); return { error: null }; },
      mfa: {
        async getAuthenticatorAssuranceLevel() { return { data: { currentLevel: db.state.aal, nextLevel: 'aal2' }, error: null }; },
        async listFactors() { return { data: { totp: db.state.aal === 'aal2' ? [{ id: 'factor', status: 'verified', factor_type: 'totp' }] : [], all: [] }, error: null }; },
        async enroll() { return { data: { id: 'factor', totp: { qr_code: 'data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22/%3E' } }, error: null }; },
        async challengeAndVerify() { db.state.aal = 'aal2'; return { data: {}, error: null }; },
        async unenroll() { return { data: {}, error: null }; }
      }
    },
    from(table) { return new Query(db, table); },
    async rpc(name, args = {}) {
      db.state.rpcCalls.push({ name, args: clone(args) });
      if (db.state.delay) await new Promise(done => setTimeout(done, db.state.delay));
      const handler = rpc[name];
      if (!handler) return { data: null, error: null };
      try {
        const result = typeof handler === 'function' ? await handler(args, db) : handler;
        if (result && typeof result === 'object' && ('data' in result || 'error' in result)) return clone(result);
        return { data: clone(result), error: null };
      } catch (error) { return { data: null, error: { message: error.message } }; }
    },
    functions: {
      async invoke(name, options) {
        db.state.rpcCalls.push({ name: 'fn:' + name, args: clone(options?.body) });
        const handler = functions[name];
        if (!handler) return { data: { error: 'Funzione non disponibile nella prova' }, error: null };
        return { data: await handler(options?.body, db), error: null };
      }
    },
    channel() {
      const channel = { on() { return channel; }, subscribe(cb) { queueMicrotask(() => cb?.('SUBSCRIBED')); return channel; }, unsubscribe() {} };
      return channel;
    },
    async removeChannel() { return 'ok'; },
    storage: {
      from() {
        return {
          getPublicUrl(path) { return { data: { publicUrl: db.state.imageUrl?.(path) || '' } }; },
          async upload() { return { data: { path: 'demo' }, error: null }; },
          async remove() { return { data: [], error: null }; }
        };
      }
    },
    emit(event) { emit(event, session()); },
    setUser(next, aalLevel = db.state.aal) { db.state.user = next; db.state.aal = aalLevel; emit(next ? 'SIGNED_IN' : 'SIGNED_OUT', session()); }
  };
  return client;
}
