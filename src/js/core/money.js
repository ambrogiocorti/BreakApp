/** Formattazione UI, mai calcolo autoritativo di contabilità o pagamenti. */
export function formatEuro(cents, locale = 'it-IT') {
  if (!Number.isSafeInteger(cents)) {
    throw new TypeError('L’importo deve essere un numero intero di centesimi.');
  }
  return new Intl.NumberFormat(locale, { style: 'currency', currency: 'EUR' }).format(cents / 100);
}
