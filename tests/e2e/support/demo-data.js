// Fictional data for browser tests and visual reviews only. Nothing here is
// shipped: names, orders and amounts are invented and never reach Supabase.
const SCHOOL = '11111111-1111-4111-8111-111111111111';
const SCHOOL_B = '22222222-2222-4222-8222-222222222222';
const SCHOOL_C = '33333333-3333-4333-8333-333333333333';
const BAR = '44444444-4444-4444-8444-444444444444';
const BAR_B = '55555555-5555-4555-8555-555555555555';
const USER = '66666666-6666-4666-8666-666666666666';
const OTHER = '77777777-7777-4777-8777-777777777777';
const GROUP = '88888888-8888-4888-8888-888888888888';
const GROUP_B = '99999999-9999-4999-8999-999999999999';

const iso = days => {
  const date = new Date(Date.now() + days * 86400000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Rome', year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
};
const TODAY = iso(0), TOMORROW = iso(1), AFTER = iso(2);

const categories = [
  ['cat-panini', 'Panini e focacce', 1], ['cat-pizza', 'Pizza al trancio', 2],
  ['cat-dolci', 'Dolci', 3], ['cat-bevande', 'Bevande', 4]
].map(([id, name, sort_order]) => ({ id, name, sort_order, school_id: SCHOOL, bar_id: BAR, is_active: true }));

const products = [
  ['p-focaccia', 'cat-panini', 'Focaccia genovese', 'Focaccia all’olio extravergine, cotta in mattinata.', 180, 'Farina di grano tenero, acqua, olio extravergine di oliva, sale, lievito', ['gluten']],
  ['p-cotto', 'cat-panini', 'Panino cotto e fontina', 'Pane al latte, prosciutto cotto e fontina.', 300, 'Pane al latte, prosciutto cotto, fontina', ['gluten', 'milk']],
  ['p-piadina', 'cat-panini', 'Piadina vegetariana', 'Verdure grigliate e crema di ricotta.', 350, 'Piadina, zucchine, melanzane, peperoni, ricotta', ['gluten', 'milk']],
  ['p-tonno', 'cat-panini', 'Panino tonno e pomodoro', '', 320, 'Pane, tonno, pomodoro, maionese', ['gluten', 'fish', 'eggs']],
  ['p-margherita', 'cat-pizza', 'Trancio margherita', 'Pomodoro e mozzarella.', 220, 'Farina, pomodoro, mozzarella, olio', ['gluten', 'milk']],
  ['p-patate', 'cat-pizza', 'Trancio patate e rosmarino', '', 230, 'Farina, patate, rosmarino, olio', ['gluten']],
  ['p-cornetto', 'cat-dolci', 'Cornetto alla crema', '', 130, 'Farina, burro, uova, latte, zucchero', ['gluten', 'milk', 'eggs']],
  ['p-crostata', 'cat-dolci', 'Crostatina alle albicocche', '', 150, 'Farina, burro, uova, confettura', ['gluten', 'milk', 'eggs']],
  ['p-acqua', 'cat-bevande', 'Acqua naturale 50 cl', '', 80, 'Acqua minerale naturale', []],
  ['p-succo', 'cat-bevande', 'Succo ACE', '', 120, 'Succo di arancia, carota e limone', []],
  ['p-te', 'cat-bevande', 'Tè freddo al limone', '', 150, '', []]
].map(([id, category_id, name, description, price_cents, ingredients, allergens]) => ({
  id, category_id, name, description, price_cents, ingredients, allergens, image_path: null,
  school_id: SCHOOL, bar_id: BAR, is_active: true, categories: { is_active: true }
}));

const windows = [
  ['w-today-1', TODAY, '10:00:00', '10:15:00'], ['w-today-2', TODAY, '12:50:00', '13:05:00'],
  ['w-tomorrow-1', TOMORROW, '10:00:00', '10:15:00'], ['w-tomorrow-2', TOMORROW, '12:50:00', '13:05:00'],
  ['w-after', AFTER, '10:00:00', '10:15:00']
].map(([id, service_date, starts_at, ends_at]) => ({ id, service_date, starts_at, ends_at, school_id: SCHOOL, bar_id: BAR, is_active: true }));

const product = id => products.find(p => p.id === id);
function order(no, status, payment, items, slot = 'w-today-1', customer = USER, minutesAgo = no) {
  const window = windows.find(w => w.id === slot);
  const lines = items.map(([id, quantity]) => ({ product_id: id, product_name: product(id).name, quantity }));
  return {
    id: 'order-' + no, display_no: no, status, payment_status: payment,
    payment_method: payment === 'paid' ? (no % 2 ? 'stripe' : 'cash') : null,
    total_cents: items.reduce((sum, [id, q]) => sum + product(id).price_cents * q, 0),
    school_id: SCHOOL, bar_id: BAR, customer_id: customer, pickup_token: 'aaaaaaaa-bbbb-4ccc-8ddd-' + String(no).padStart(12, '0'),
    created_at: new Date(Date.now() - minutesAgo * 60000).toISOString(),
    pickup_windows: { service_date: window.service_date, starts_at: window.starts_at, ends_at: window.ends_at },
    order_items: lines
  };
}

export function demoOrders() {
  return [
    order(128, 'confirmed', 'due', [['p-cotto', 1], ['p-margherita', 1], ['p-succo', 1]], 'w-today-1', OTHER, 3),
    order(129, 'confirmed', 'paid', [['p-focaccia', 2]], 'w-today-1', OTHER, 4),
    order(130, 'confirmed', 'due', [['p-piadina', 1], ['p-acqua', 1]], 'w-today-1', OTHER, 5),
    order(131, 'preparing', 'paid', [['p-cotto', 2], ['p-te', 2]], 'w-today-1', OTHER, 8),
    order(126, 'ready', 'due', [['p-margherita', 1], ['p-acqua', 1]], 'w-today-1', OTHER, 12),
    order(125, 'ready', 'paid', [['p-cornetto', 2]], 'w-today-1', OTHER, 14),
    order(132, 'confirmed', 'due', [['p-tonno', 1]], 'w-today-2', OTHER, 2),
    order(120, 'delivered', 'paid', [['p-focaccia', 1]], 'w-today-1', OTHER, 60),
    order(119, 'cancelled', 'due', [['p-crostata', 1]], 'w-today-1', OTHER, 70),
    order(141, 'ready', 'due', [['p-cotto', 1], ['p-succo', 1]], 'w-today-1', USER, 20),
    order(142, 'confirmed', 'paid', [['p-focaccia', 1], ['p-acqua', 1]], 'w-tomorrow-1', USER, 30),
    order(97, 'delivered', 'paid', [['p-piadina', 1]], 'w-today-1', USER, 2880)
  ];
}

const memberships = {
  customer: [],
  staff: [{ id: 'm1', school_id: SCHOOL, user_id: USER, membership_status: 'active', schools: { id: SCHOOL, name: 'Istituto Demo Galilei', slug: 'demo-galilei' },
    role_assignments: [{ role_code: 'bartender' }, { role_code: 'school_admin' }, { role_code: 'warehouse_manager' }] }]
};

export function demoState(as = 'student') {
  const staff = ['bartender', 'admin', 'warehouse'].includes(as);
  const platform = as === 'platform';
  const guest = as === 'guest';
  const user = as === 'signedout' ? null : {
    id: USER,
    email: guest ? 'ospite-1@guest.breakapp.invalid' : platform ? 'piattaforma@example.invalid' : staff ? 'giulia.rossi@example.invalid' : 'marco.bianchi@example.invalid',
    email_confirmed_at: guest ? null : '2026-10-01T08:00:00Z',
    app_metadata: guest ? { guest: true } : {},
    user_metadata: guest ? { display_name: 'Luca (ospite)' } : {}
  };
  const role = { bartender: 'bartender', admin: 'school_admin', warehouse: 'warehouse_manager', platform: 'platform_admin' }[as] || 'customer';
  const tables = {
    schools: [
      { id: SCHOOL, name: 'Istituto Demo Galilei', is_active: true, latitude: 45.52, longitude: 9.33, max_active_approvals: 3, no_show_penalty_minutes: 0, require_guest_class: false, order_radius_m: 1000, booking_horizon_days: 30, cancellation_cutoff_minutes: 10, max_unpaid_orders: 3 },
      { id: SCHOOL_B, name: 'Liceo Demo Montale', is_active: true, latitude: 45.5, longitude: 9.3 },
      { id: SCHOOL_C, name: 'Istituto Demo Volta', is_active: false, latitude: 45.5, longitude: 9.3 }
    ],
    bars: [
      { id: BAR, school_id: SCHOOL, name: 'Bar centrale', is_active: true },
      { id: BAR_B, school_id: SCHOOL, name: 'Chiosco del cortile', is_active: true },
      { id: 'bar-m', school_id: SCHOOL_B, name: 'Bar Montale', is_active: true },
      { id: 'bar-v', school_id: SCHOOL_C, name: 'Bar Volta', is_active: true }
    ],
    school_memberships: staff ? memberships.staff : [],
    categories, products, pickup_windows: windows,
    bar_opening_hours: Array.from({ length: 7 }, (_, weekday) => ({ school_id: SCHOOL, bar_id: BAR, weekday, starts_at: '07:30:00', ends_at: '14:00:00' })),
    bar_closures: [], bar_service_state: [{ school_id: SCHOOL, bar_id: BAR, accepting_orders: true, reason: null }],
    bar_service_events: [{ bar_id: BAR, school_id: SCHOOL, kind: 'resume', reason: 'Servizio regolare', created_at: new Date(Date.now() - 3600000).toISOString() }],
    daily_stock: products.slice(0, 8).map((p, i) => ({ id: 'stock-' + p.id, school_id: SCHOOL, bar_id: BAR, product_id: p.id, service_date: TODAY, capacity: [40, 30, 20, 15, 24, 24, 30, 20][i], allocated: [6, 9, 2, 1, 4, 0, 4, 0][i] })),
    orders: demoOrders(),
    customer_favorites: [{ user_id: USER, product_id: 'p-focaccia', products: { id: 'p-focaccia', name: 'Focaccia genovese', bar_id: BAR, price_cents: 180 } }],
    customer_notifications: [{ id: 'n1', user_id: USER, message: 'Il tuo ordine 141 è pronto al bar centrale.', created_at: new Date(Date.now() - 600000).toISOString(), read_at: null, kind: 'order' }],
    support_tickets: [], support_messages: [], support_attachments: [], support_reopen_requests: [],
    school_classes: [{ school_id: SCHOOL, name: '4A', active: true }, { school_id: SCHOOL, name: '5B', active: true }]
  };
  const groupDetail = {
    id: GROUP, title: 'Merenda 4A', status: 'draft', coordinator: true, my_status: 'accepted', accepting_members: true, requires_approval: false,
    max_members: null, school_id: SCHOOL, bar_id: BAR, pickup_window_id: 'w-tomorrow-1', invite_token: 'abababab-abab-4bab-8bab-abababababab', my_ready: false,
    my_items: [{ product_id: 'p-focaccia', quantity: 1 }, { product_id: 'p-succo', quantity: 1 }], totals: { count: 7, total_cents: 1460 },
    members: [
      { member_id: USER, status: 'accepted', ready: false, line_count: 2 },
      { member_id: OTHER, status: 'accepted', ready: true, line_count: 3 },
      { member_id: 'aaaaaaaa-1111-4111-8111-111111111111', status: 'accepted', ready: false, line_count: 2 },
      { member_id: 'bbbbbbbb-1111-4111-8111-111111111111', status: 'pending', ready: false, line_count: 0 }
    ]
  };
  const rpc = {
    has_current_platform_admin_role: platform, is_current_platform_admin: platform,
    list_my_group_drafts: guest ? [] : [
      { id: GROUP, title: 'Merenda 4A', coordinator: true, my_status: 'accepted', status: 'draft' },
      { id: GROUP_B, title: 'Laboratorio di chimica', coordinator: false, my_status: 'accepted', status: 'confirmed' }
    ],
    group_draft_details: ({ p_group_id }) => p_group_id === GROUP ? groupDetail : { ...groupDetail, id: GROUP_B, title: 'Laboratorio di chimica', status: 'confirmed', coordinator: false, invite_token: null, members: [] },
    replace_group_personal_cart: ({ p_items }) => { groupDetail.my_items = p_items; return null; },
    set_group_personal_ready: ({ p_ready }) => { groupDetail.my_ready = p_ready; groupDetail.members[0].ready = p_ready; return null; },
    group_payable_lines: [
      { line_id: 'l1', product_name: 'Focaccia genovese', quantity: 1, amount_cents: 180, payment_state: 'available', beneficiary_id: USER },
      { line_id: 'l2', product_name: 'Succo ACE', quantity: 1, amount_cents: 120, payment_state: 'paid', beneficiary_id: USER }
    ],
    list_my_confirmed_group_orders: [{ id: 'go-1', group_id: GROUP_B, title: 'Laboratorio di chimica', status: 'confirmed', coordinator: false }],
    group_order_details: { id: 'go-1', status: 'confirmed', total_cents: 2140, paid_cents: 900, due_cents: 1240, coordinator: false, lines: [{ quantity: 4, name: 'Focaccia genovese', subtotal_cents: 720 }] },
    list_staff_group_orders: [{ id: 'go-1', title: 'Laboratorio di chimica', status: 'confirmed', total_cents: 2140 }, { id: 'go-2', title: 'Merenda 3C', status: 'ready', total_cents: 1180 }],
    list_staff_pending_cash_refunds: { items: [], total: 0, has_more: false },
    workflow_order_details: { due_cents: 520, total_cents: 520, bar_id: BAR, lines: [] },
    list_order_approvals: [], list_order_changes: [], list_cash_refund_obligations: [], my_payment_documents: [],
    list_school_stock_conflicts: [], list_school_promotions: [],
    cash_workspace: { sessions: [{ id: 'cccccccc-0000-4000-8000-000000000001', bar_id: BAR, actor_id: USER, opening_cents: 5000, current_expected_cents: 7340, opened_at: new Date(Date.now() - 2 * 3600000).toISOString(), closed_at: null },
      { id: 'cccccccc-0000-4000-8000-000000000002', bar_id: BAR, actor_id: OTHER, opening_cents: 5000, expected_cents: 18250, counted_cents: 18200, closing_reason: 'Differenza di 50 centesimi verificata con il collega.', opened_at: new Date(Date.now() - 26 * 3600000).toISOString(), closed_at: new Date(Date.now() - 20 * 3600000).toISOString(), adjustments_cents: 0 }],
      entries: [{ created_at: new Date(Date.now() - 1800000).toISOString(), kind: 'receipt', amount_cents: 520, reason: 'Ordine 124' }, { created_at: new Date(Date.now() - 3600000).toISOString(), kind: 'withdrawal', amount_cents: 1000, reason: 'Acquisto ghiaccio dal fornitore' }],
      unassigned_cents: 0 },
    school_financial_report: null, list_school_offline_events: [], get_my_notification_preferences: null,
    platform_list_school_staff: [{ user_id: USER, email: 'giulia.rossi@example.invalid', role_code: 'bartender' }],
    my_support_group_references: [], my_guest_email_recovery_status: false
  };
  const ctxKey = role === 'platform_admin' ? 'platform:platform_admin' : SCHOOL + ':' + role;
  return { user, tables, rpc, aal: 'aal2', storageKey: ctxKey };
}
export const DEMO_IDS = { SCHOOL, BAR, USER, GROUP };
