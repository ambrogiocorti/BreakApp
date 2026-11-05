// Turns technical failures into sentences a student or a bartender can act on.
// Server messages written in Italian for people (raised by our RPCs) are kept;
// raw network, database or library errors are replaced.
const TECHNICAL=[
  [/failed to fetch|networkerror|load failed|network request failed|fetch failed/i,'Connessione assente o instabile. Controlla la rete e riprova.'],
  [/jwt|token (is )?expired|invalid refresh token|session.*(expired|missing)/i,'La sessione è scaduta. Accedi di nuovo.'],
  [/permission denied|row-level security|violates row level|not authori[sz]ed|42501/i,'Non hai i permessi per questa operazione con il ruolo attuale.'],
  [/duplicate key|already exists|23505/i,'Questo elemento esiste già.'],
  [/violates foreign key|23503/i,'L’operazione non è possibile perché l’elemento è collegato ad altri dati.'],
  [/violates check constraint|23514|invalid input syntax|22P02/i,'Alcuni dati non sono validi. Controlla i campi e riprova.'],
  [/timeout|timed out|57014/i,'Il server non ha risposto in tempo. Riprova tra poco.'],
  [/rate limit|too many requests|429/i,'Troppi tentativi ravvicinati. Attendi qualche istante e riprova.'],
  [/function .* does not exist|could not find the function|PGRST202/i,'Questa funzione non è ancora attiva sul server.'],
  [/PGRST|postgres|supabase|syntax error|undefined|null|TypeError|ReferenceError/i,null]
];
export function friendlyError(error,fallback='Operazione non riuscita. Riprova tra poco.'){
  const text=String(error?.message||error||'').trim();
  if(!text)return fallback;
  for(const [pattern,replacement] of TECHNICAL)if(pattern.test(text))return replacement||fallback;
  return text;
}
