import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=path=>readFileSync(new URL('../../'+path,import.meta.url),'utf8');

test('browser push registration transfers ownership atomically on the server',()=>{
 const notifications=read('src/js/features/notifications/notifications.js');
 assert.match(notifications,/client\.rpc\('register_my_push_subscription'/);
 assert.doesNotMatch(notifications,/from\('push_subscriptions'\)\.insert/);
});

test('logout revokes browser endpoint before ending the authenticated session',()=>{
 const auth=read('src/js/features/auth/auth.js');
 const notifications=read('src/js/features/notifications/notifications.js');
 assert.ok(auth.indexOf('await revokeDevicePush(client)') <
   auth.indexOf("client.auth.signOut()"));
 assert.match(notifications,/client\.from\('push_subscriptions'\)/);
 assert.match(notifications,/await subscription\.unsubscribe\(\)/);
 assert.match(auth,/pushWarning/);
});

test('server restricts delivery to current subscriber and notice owner',()=>{
 const migration=read('supabase/sql/24_push_device_ownership.sql');
 assert.match(migration,/create unique index if not exists push_subscriptions_endpoint_unique/);
 assert.match(migration,/s\.user_id=j\.user_id/);
 assert.match(migration,/n\.user_id=j\.user_id/);
 assert.match(migration,/status='dead'/);
});
