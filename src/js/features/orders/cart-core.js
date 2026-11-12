// BreakApp: solo il server decide prezzi finali e disponibilità. Questo modulo
// gestisce esclusivamente il carrello provvisorio nel browser.
export function cartAdd(items, productId, quantity = 1) {
  if (typeof productId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(productId)) {
    throw new Error('Prodotto non valido');
  }
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > 1000) {
    throw new Error('Quantità non valida');
  }
  const next = new Map(items.map((item) => [item.product_id, item.quantity]));
  const count = (next.get(productId) || 0) + quantity;
  if (count > 1000) throw new Error('Quantità massima per prodotto raggiunta');
  next.set(productId, count);
  return [...next].map(([product_id, quantity]) => ({ product_id, quantity }));
}

export function cartSetQuantity(items, productId, quantity) {
  if (!Number.isInteger(quantity) || quantity < 0 || quantity > 1000) {
    throw new Error('Quantità non valida');
  }
  const next = items.filter((item) => item.product_id !== productId);
  if (quantity > 0) next.push({ product_id: productId, quantity });
  return next;
}

export function cartSummary(items, products) {
  const priceById = new Map(products.map((p) => [p.id, p]));
  let count = 0;
  let totalCents = 0;
  const lines = [];
  for (const item of items) {
    if (!Number.isInteger(item.quantity) || item.quantity < 1) throw new Error('Quantità non valida');
    const product = priceById.get(item.product_id);
    if (!product || !product.is_active || !Number.isInteger(product.price_cents)) {
      throw new Error('Il catalogo è cambiato. Aggiorna il carrello.');
    }
    count += item.quantity;
    totalCents += product.price_cents * item.quantity;
    if (!Number.isSafeInteger(totalCents) || totalCents > 999999999) {
      throw new Error('Importo non valido');
    }
    lines.push({ ...item, name: product.name, unitCents: product.price_cents, subtotalCents: product.price_cents * item.quantity });
  }
  return { count, totalCents, lines };
}

export function safeCartParse(serialized, expectedBarId) {
  try {
    const data = JSON.parse(serialized);
    if (!data || data.bar_id !== expectedBarId || !Array.isArray(data.items) || data.items.length > 100) return [];
    const known = new Set();
    return data.items.filter((item) => {
      if (typeof item.product_id !== 'string' || known.has(item.product_id)
        || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 1000) return false;
      known.add(item.product_id);
      return true;
    }).map(({ product_id, quantity }) => ({ product_id, quantity }));
  } catch {
    return [];
  }
}

export function toRpcItems(items) {
  return items.map(({ product_id, quantity }) => ({ product_id, quantity }));
}
