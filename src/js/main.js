import '../css/base.css';
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

initializeTheme();
const client = initializeAuth(readSupabaseConfig(import.meta.env));
initializePublicMenu(client);
initializeOrders(client);
initializePickupQr(client);
initializeBarService(client);
initializeSupportCenter(client);
initializeWarehouseInventory(client);
initializeWorkspaceDashboards(client);
initializePlatformPilot(client);
initializeGroupDrafts(client);
initializeWorkspace(client);

// Cache statica soltanto: nessuna vendita, consegna o incasso offline in Fase 1.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`, { scope: import.meta.env.BASE_URL }).catch(() => { /* l'app online resta utilizzabile */ });
  });
}
