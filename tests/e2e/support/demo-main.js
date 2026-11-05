// Full application bootstrap for visual reviews and browser tests. It mirrors
// src/js/main.js but injects the in-memory client and fictional data.
import '../../../src/css/app.css';
import { initializeTheme } from '../../../src/js/core/theme.js';
import { initializeAuth } from '../../../src/js/features/auth/auth.js';
import { initializePublicMenu } from '../../../src/js/features/menu/menu.js';
import { initializeOrders } from '../../../src/js/features/orders/orders.js';
import { initializePickupQr } from '../../../src/js/features/orders/pickup-qr.js';
import { initializeSupportCenter } from '../../../src/js/features/support/support.js';
import { initializeWorkspace } from '../../../src/js/features/shell/workspace.js';
import { initializeGroupDrafts } from '../../../src/js/features/groups/groups.js';
import { initializeInAppNotifications } from '../../../src/js/features/notifications/notifications.js';
import { initializeOrderWorkflows } from '../../../src/js/features/operations/workflows.js';
import { initializeCompletionUI } from '../../../src/js/features/operations/completion-ui.js';
import { initializeGuestAccess } from '../../../src/js/features/auth/guest.js';
import { createRoleModuleLoader } from '../../../src/js/role-modules.js';
import { createMockClient } from './mock-client.js';
import { demoState } from './demo-data.js';

const params = new URLSearchParams(location.search);
const as = params.get('as') || 'student';
const state = demoState(as);
try { localStorage.setItem('breakapp:last-workspace-context', state.storageKey); } catch { /* storage denied */ }
const mock = createMockClient({ tables: state.tables, rpc: state.rpc, user: state.user, aal: state.aal });
window.demo = { client: mock, as };
const fixedPosition = { coords: { latitude: 45.52, longitude: 9.33, accuracy: 25 }, timestamp: Date.now() };
if (params.get('geo') !== 'native') {
  Object.defineProperty(navigator, 'geolocation', { configurable: true, value: {
    watchPosition(ok, fail) {
      const mode = window.demo.geo || 'ok';
      const id = setTimeout(() => {
        if (mode === 'denied') fail({ code: 1 });
        else if (mode === 'coarse') ok({ coords: { ...fixedPosition.coords, accuracy: 900 }, timestamp: Date.now() });
        else ok({ coords: fixedPosition.coords, timestamp: Date.now() });
      }, 120);
      return id;
    },
    clearWatch(id) { clearTimeout(id); }
  } });
}
initializeTheme();
const client = initializeAuth({ configured: true, url: 'https://demo.invalid', publishableKey: 'demo' }, () => mock);
initializeGuestAccess(client);
initializePublicMenu(client);
initializeOrders(client);
initializePickupQr(client);
initializeSupportCenter(client);
initializeGroupDrafts(client);
initializeInAppNotifications(client);
initializeCompletionUI(client);
initializeOrderWorkflows(client);
// Same on-demand staff chunk as src/js/main.js.
const roleModules = createRoleModuleLoader(client);
roleModules.warm();
initializeWorkspace(client, { prepareRole: role => roleModules.prepare(role) });
window.demo.roleModules = roleModules;
window.demo.ready = true;
