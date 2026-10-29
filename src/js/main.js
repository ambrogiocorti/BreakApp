import '../css/base.css';
import '../css/workspace.css';
import '../css/groups.css';
import { readSupabaseConfig } from './core/config.js';
import { initializeTheme } from './core/theme.js';
import { initializeAuth } from './features/auth/auth.js';
import { initializePublicMenu } from './features/menu/menu.js';
import { initializeOrders } from './features/orders/orders.js';
import { initializePickupQr } from './features/orders/pickup-qr.js';
import { initializeBarService } from './features/operations/bar-service.js';
import { initializeSupportCenter } from './features/support/support.js';
import { initializeWorkspace } from './features/shell/workspace.js';
import { initializeWarehouseInventory } from './features/warehouse/inventory.js';
import { initializeWorkspaceDashboards } from './features/shell/dashboards.js';
import { initializePlatformPilot } from './features/shell/platform-pilot.js';
import { initializeGroupDrafts } from './features/groups/groups.js';
import { initializeGroupService } from './features/groups/group-service.js';
import { initializeInAppNotifications } from './features/notifications/notifications.js';
import { initializeOfflineTerminal } from './features/offline/terminal.js';
import { initializeOfflineReview } from './features/offline/review.js';
import { initializeCashWorkspace } from './features/operations/cash.js';
import { initializeReports } from './features/shell/reports.js';
import { initializeOrderWorkflows } from './features/operations/workflows.js';
import { initializeCompletionUI } from './features/operations/completion-ui.js';
import { initializeGuestAccess } from './features/auth/guest.js';

initializeTheme();
const client = initializeAuth(readSupabaseConfig(import.meta.env));
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
const offlineTerminal=initializeOfflineTerminal(client);
initializeCashWorkspace(client,offlineTerminal);
initializeReports(client);
initializeOfflineReview(client);
initializeCompletionUI(client);
initializeOrderWorkflows(client);
initializeWorkspace(client);

// Static shell cache; operational snapshots and pending events use the encrypted vault.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`, { scope: import.meta.env.BASE_URL }).catch(() => { /* l'app online resta utilizzabile */ });
  });
}
