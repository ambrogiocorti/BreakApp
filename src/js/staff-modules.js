// Controllers used only by staff and administrators. Customers never download
// this chunk: main.js loads it through role-modules.js when a staff, admin or
// Super Admin context is about to open. Every panel here starts [hidden] in
// index.html and stays hidden until its controller verifies the context.
import { initializeBarService } from './features/operations/bar-service.js';
import { initializeWarehouseInventory } from './features/warehouse/inventory.js';
import { initializeWorkspaceDashboards } from './features/shell/dashboards.js';
import { initializePlatformPilot } from './features/shell/platform-pilot.js';
import { initializeGroupService } from './features/groups/group-service.js';
import { initializeOfflineTerminal } from './features/offline/terminal.js';
import { initializeOfflineReview } from './features/offline/review.js';
import { initializeCashWorkspace } from './features/operations/cash.js';
import { initializeReports } from './features/shell/reports.js';

export function initializeStaffModules(client){
  initializeBarService(client);
  initializeWarehouseInventory(client);
  initializeWorkspaceDashboards(client);
  initializePlatformPilot(client);
  initializeGroupService(client);
  const offlineTerminal=initializeOfflineTerminal(client);
  initializeCashWorkspace(client,offlineTerminal);
  initializeReports(client);
  initializeOfflineReview(client);
}
