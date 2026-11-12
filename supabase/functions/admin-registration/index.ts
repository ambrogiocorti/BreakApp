import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import {createAdminRegistrationHandler} from './handler.mjs';
Deno.serve(createAdminRegistrationHandler({createClient,env:(name:string)=>Deno.env.get(name)}));
