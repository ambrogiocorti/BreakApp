// Endpoint disattivato: la registrazione self-service degli account
// amministratore è stata rimossa (gli Admin sono creati dal Super Admin).
import {createAdminRegistrationHandler} from './handler.mjs';
Deno.serve(createAdminRegistrationHandler());
