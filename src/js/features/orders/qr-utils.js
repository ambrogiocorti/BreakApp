export const PICKUP_QR_PREFIX = 'breakapp:pickup:';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function makePickupQrValue(token) {
  if (typeof token !== 'string' || !UUID.test(token)) throw new Error('Token QR non valido');
  return PICKUP_QR_PREFIX + token.toLowerCase();
}
export function parsePickupQrValue(value) {
  if (typeof value !== 'string' || !value.startsWith(PICKUP_QR_PREFIX)) return null;
  const token=value.slice(PICKUP_QR_PREFIX.length);
  return UUID.test(token) ? token.toLowerCase() : null;
}
export function parseOrderDisplayNumber(value) {
  const text=String(value ?? '').trim();
  if(!/^[1-9][0-9]{0,14}$/.test(text)) return null;
  return text;
}
