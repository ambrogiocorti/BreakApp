# BreakApp — QR ordine individuale e scanner Barista

## Rilascio incrementale

- Biglietto QR del cliente generato in locale; contiene solo il token personale UUID casuale emesso dal server, **non** dati personali o email.
- Token rappresentato nel formato `breakapp:pickup:<uuid>` e mostrato solo dopo caricamento di un ordine reale del cliente.
- Scanner da browser tramite `BarcodeDetector` e `getUserMedia`, avviato **solo con azione esplicita** del personale; la fotocamera è chiusa quando il dialogo si chiude.
- Fallback con numero d'ordine, indipendente dal supporto del browser.
- Anteprima dati/quantità/stato/pagamento recuperata tramite Supabase e filtrata da RLS.
- L'incasso al ritiro e la consegna non avvengono tramite la semplice scansione; sono comandi distinti con conferma, chiamano RPC autorizzate e ricontrollano lo stato sul server.
- La consegna viene rifiutata quando non pronto o non saldato; ritiri ripetuti devono essere rifiutati dalla state machine DB.
- La lib QR è self-hosted in `public/vendor`, con licenza MIT e senza richieste verso CDN esterni. Non si generano QR sul server per questo flusso.

## Limitazioni

- `BarcodeDetector` non è disponibile su tutti i browser: usare il numero ordine.
- Il numero ordine è un fallback e la sua ricerca non sostituisce il controllo dell'addetto.
- La protezione di un QR non significa identificazione biometrica/fisica del portatore: il personale deve verificare che l'ordine richiesto corrisponda alla consegna.
- Non ancora integrati: QR di gruppo e lease ritiro 10 min; operatività QR offline; firme dinamiche rotanti e monitor pubblico configurabile.

## Accettazione

1. Caricare un ordine reale tramite cliente e verificare display QR senza informazioni personali.
2. Leggere QR su smartphone supportato e connettersi come Barista autorizzato.
3. Cercare lo stesso ordine per numero quando manca `BarcodeDetector`.
4. Verificare che ordine non pronto non possa essere consegnato.
5. Verificare che ordine pronto ma da pagare non possa essere consegnato.
6. Dopo incasso effettivo, confermare la consegna e verificarla su Supabase.
7. Ritentare la consegna del medesimo QR: operazione server deve essere negata.
8. Verificare che personale di scuola B non possa leggere ordine e token della scuola A.
9. Con browser senza permesso camera, scanner non parte; ricerca manuale disponibile.
10. Al logout, stream video e dialoghi devono chiudersi.
