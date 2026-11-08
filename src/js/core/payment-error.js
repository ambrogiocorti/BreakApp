import {friendlyError} from './errors.js';

// Supabase FunctionsHttpError hides the useful JSON error behind context.
// Show only our server's explicit error string, never a raw response payload.
export async function paymentError(error){
  const response=error?.context;
  if(response&&typeof response.json==='function'){
    try{
      const body=await response.json();
      if(body&&typeof body.error==='string'&&body.error.trim()){
        return new Error(friendlyError(body.error.trim().slice(0,400),'Pagamento non disponibile.'));
      }
    }catch{/* Non-JSON responses are handled by status below. */}
  }
  const status=Number(response?.status);
  if(status===401)return new Error('Sessione scaduta. Accedi di nuovo e riprova.');
  if(status===403)return new Error('Pagamento non autorizzato per questo account o sito.');
  if(status===404)return new Error('Servizio di pagamento non distribuito. Contatta il supporto.');
  if(status===429)return new Error('Troppi tentativi di pagamento. Attendi e riprova.');
  if(status>=500)return new Error('Servizio di pagamento temporaneamente non disponibile (HTTP '+status+').');
  return new Error(friendlyError(error,'Non è stato possibile contattare il servizio di pagamento.'));
}
