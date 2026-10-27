# ADR 002 — Ordini, variazioni economiche e snapshot offline

Stato: implementato. Data: 27 ottobre 2026.

Gli ordini grandi sono richieste persistenti separate dalla riserva. La sola presenza di un Barista abilita attivazioni limitate con lease di dieci minuti; il cliente vede sempre che manca l'approvazione. Un incremento sopra soglia non può aggirare la verifica tramite una modifica successiva.

Le modifiche individuali archiviano le vecchie righe e salvano versioni immutabili. Le allocazioni dei pagamenti mantengono i riferimenti storici. Il saldo deriva da pagamenti verificati, crediti richiesti e incassi reali; nessuna modifica del browser decide prezzi o importi. I supplementi di gruppo sono obbligazioni intere, collegate a riga e beneficiario. Le restituzioni cash hanno un registro distinto: promessa e consegna fisica non coincidono.

Gli handler di rimborso immediato e schedulato usano la stessa chiave Stripe e gli stessi parametri. Un retry concorrente non crea una seconda operazione presso il provider. Il ledger considera i crediti pendenti per evitare nuovi incassi o rimborsi eccessivi; lo stato finale rimane dipendente dal webhook firmato.

Il manifest offline è una prova conservata dal server, vincolata a operatore, scuola, dispositivo e generazione. Include privatamente gli ID dei pagamenti già acquisiti: il confronto per timestamp da solo non determina quale pagamento sia duplicato. La risoluzione automatica usa solo pagamenti successivi allo snapshot; i casi incerti richiedono revisione.

Una conta fisica motivata può essere inferiore alle allocazioni. L'eccezione al vincolo è autorizzata da una riga privata legata alla transazione, non da una variabile impostabile dal client. Le righe scoperte seguono la priorità di ritiro e il flusso di consenso/rimborso. Per default viene trattata tutta la riga coinvolta; non si introduce una consegna parziale implicita.

Proposte di configurazione adottate: link ospite di 30 giorni; penalità no-show disabilitata per default, configurabile fino a sette giorni; eliminazione dei payload QR dei manifest dopo 90 giorni se tutti gli eventi sono risolti. Questi dettagli non alterano diritti dei pagatori, vincoli di ruolo o conservazione del ledger.

Il recupero ospite usa una prova della casella attraverso Supabase Auth e un collegamento privato verso il soggetto originale. La richiesta contiene solo l'hash SHA-256 dell'email, scade in un'ora e richiede conferma esplicita nell'identità verificata. Non si aggiorna l'indirizzo sintetico, perché Secure Email Change potrebbe richiedere conferma anche sulla vecchia casella inesistente. Un'identità email non può essere riassegnata a un altro ospite già collegato; nessun dato finanziario cambia titolare.
