// Registrazione account amministratore (@admin.breakapp.it) sbloccata solo da un
// codice di invito valido emesso dal Super Admin. Senza invito pendente
// corrispondente non viene creato alcun account.
import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import {createAdminRegistrationHandler} from './handler.mjs';
Deno.serve(createAdminRegistrationHandler({createClient,env:(name:string)=>Deno.env.get(name)}));
