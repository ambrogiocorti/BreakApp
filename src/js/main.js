import '../css/app.css';
import { readSupabaseConfig } from './core/config.js';
import { initializeTheme } from './core/theme.js';
import { initializeAuth } from './features/auth/auth.js';
import { initializePublicMenu } from './features/menu/menu.js';
import { initializeOrders } from './features/orders/orders.js';
import { initializePickupQr } from './features/orders/pickup-qr.js';
import { initializeSupportCenter } from './features/support/support.js';
import { initializeWorkspace } from './features/shell/workspace.js';
import { initializeGroupDrafts } from './features/groups/groups.js';
import { initializeInAppNotifications } from './features/notifications/notifications.js';
import { initializeOrderWorkflows } from './features/operations/workflows.js';
import { initializeCompletionUI } from './features/operations/completion-ui.js';
import { initializeGuestAccess } from './features/auth/guest.js';
import { createRoleModuleLoader } from './role-modules.js';

initializeTheme();
const client = initializeAuth(readSupabaseConfig(import.meta.env));
initializeGuestAccess(client);
initializePublicMenu(client);
initializeOrders(client);
initializePickupQr(client);
initializeSupportCenter(client);
initializeGroupDrafts(client);
initializeInAppNotifications(client);
initializeCompletionUI(client);
initializeOrderWorkflows(client);
// Staff and admin controllers live in a separate chunk (see role-modules.js).
const roleModules=client?createRoleModuleLoader(client):null;
roleModules?.warm();
initializeWorkspace(client,{prepareRole:role=>roleModules?.prepare(role)});

// Static shell cache; operational snapshots and pending events use the encrypted vault.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`, { scope: import.meta.env.BASE_URL }).catch(() => { /* l'app online resta utilizzabile */ });
  });
}
