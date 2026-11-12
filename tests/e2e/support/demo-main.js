// Full application bootstrap for visual reviews and browser tests. It mirrors
// src/js/main.js but injects the in-memory client and fictional data.
import { initializeSingleChoiceFields } from '../../../src/js/core/single-choice.js';
import '../../../src/css/app.css';
import { initializeTheme } from '../../../src/js/core/theme.js';
import { initializeAuth } from '../../../src/js/features/auth/auth.js';
import { initializePublicMenu } from '../../../src/js/features/menu/menu.js';
import { initializeOrders } from '../../../src/js/features/orders/orders.js';
import { initializePickupQr } from '../../../src/js/features/orders/pickup-qr.js';
import { initializeBarService } from '../../../src/js/features/operations/bar-service.js';
import { initializeSupportCenter } from '../../../src/js/features/support/support.js';
import { initializeWorkspace } from '../../../src/js/features/shell/workspace.js';
import { initializeWarehouseInventory } from '../../../src/js/features/warehouse/inventory.js';
import { initializeWorkspaceDashboards } from '../../../src/js/features/shell/dashboards.js';
import { initializePlatformPilot } from '../../../src/js/features/shell/platform-pilot.js';
import { initializeGroupDrafts } from '../../../src/js/features/groups/groups.js';
import { initializeGroupService } from '../../../src/js/features/groups/group-service.js';
import { initializeInAppNotifications } from '../../../src/js/features/notifications/notifications.js';
import { initializeOfflineTerminal } from '../../../src/js/features/offline/terminal.js';
import { initializeOfflineReview } from '../../../src/js/features/offline/review.js';
import { initializeCashWorkspace } from '../../../src/js/features/operations/cash.js';
import { initializeReports } from '../../../src/js/features/shell/reports.js';
import { initializeOrderWorkflows } from '../../../src/js/features/operations/workflows.js';
import { initializeCompletionUI } from '../../../src/js/features/operations/completion-ui.js';
import { initializeSchoolAdmin } from '../../../src/js/features/operations/school-admin.js';
import { initializeGuestAccess } from '../../../src/js/features/auth/guest.js';
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
initializeSingleChoiceFields();
const client = initializeAuth({ configured: true, url: 'https://demo.invalid', publishableKey: 'demo' }, () => mock);
initializeGuestAccess(client);
initializePublicMenu(client);
initializeOrders(client);
initializePickupQr(client);
initializeBarService(client);
initializeSupportCenter(client);
initializeWarehouseInventory(client);
initializeWorkspaceDashboards(client);
initializePlatformPilot(client);
initializeGroupDrafts(client);
initializeGroupService(client);
initializeInAppNotifications(client);
const offlineTerminal = initializeOfflineTerminal(client);
initializeCashWorkspace(client, offlineTerminal);
initializeReports(client);
initializeOfflineReview(client);
initializeCompletionUI(client);
initializeSchoolAdmin(client);
initializeOrderWorkflows(client);
initializeWorkspace(client);
window.demo.ready = true;
