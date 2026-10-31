const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');

function pct(amount, percent) {
  return Math.round((amount * percent) / 100);
}

// Tentukan metode penerimaan dari nama opsi FULFILLMENT
function detectReceiveMethod(name) {
  const n = (name || '').toLowerCase();
  if (n.includes('jemput')) return 'PICKUP_DELIVERY';
  if (n.includes('antar')) return 'DELIVERY';
  return 'SELF_PICKUP';
}

/**
 * input: {
 *   items: [{ serviceId, quantity, notes?, addonIds?: number[] }],
 *   speedId?, fulfillmentId?, discount?
 * }
 * businessId: layanan dan opsi hanya boleh milik usaha ini.
 * Mengembalikan rincian harga lengkap (snapshot) tanpa menyimpan apa pun.
 */
async function calculate(input, businessId) {
  if (!businessId) throw new AppError('Usaha tidak diketahui', 400);

  const serviceIds = [...new Set(input.items.map((i) => i.serviceId))];
  const addonIds = [...new Set(input.items.flatMap((i) => i.addonIds || []))];

  const [services, addons, speed, fulfillment] = await Promise.all([
    prisma.service.findMany({ where: { id: { in: serviceIds }, businessId } }),
    addonIds.length
      ? prisma.serviceOption.findMany({
          where: { id: { in: addonIds }, type: 'ADDON', businessId },
        })
      : [],
    input.speedId
      ? prisma.serviceOption.findFirst({
          where: { id: input.speedId, type: 'SPEED', businessId },
        })
      : null,
    input.fulfillmentId
      ? prisma.serviceOption.findFirst({
          where: { id: input.fulfillmentId, type: 'FULFILLMENT', businessId },
        })
      : null,
  ]);

  const serviceMap = new Map(services.map((s) => [s.id, s]));
  const addonMap = new Map(addons.map((a) => [a.id, a]));

  if (input.speedId && !speed) throw new AppError('Opsi kecepatan tidak ditemukan', 400);
  if (speed && !speed.isActive) throw new AppError(`Kecepatan "${speed.name}" tidak aktif`, 400);
  if (input.fulfillmentId && !fulfillment)
    throw new AppError('Opsi penerimaan tidak ditemukan', 400);
  if (fulfillment && !fulfillment.isActive)
    throw new AppError(`Penerimaan "${fulfillment.name}" tidak aktif`, 400);

  let servicesSubtotal = 0;
  let addonsTotal = 0;

  const items = input.items.map((it) => {
    const service = serviceMap.get(it.serviceId);
    if (!service) throw new AppError(`Layanan id ${it.serviceId} tidak ditemukan`, 400);
    if (!service.isActive) throw new AppError(`Layanan "${service.name}" tidak aktif`, 400);

    const baseTotal = Math.round(service.price * it.quantity);

    const itemAddons = (it.addonIds || []).map((aid) => {
      const a = addonMap.get(aid);
      if (!a) throw new AppError(`Add-on id ${aid} tidak ditemukan`, 400);
      if (!a.isActive) throw new AppError(`Add-on "${a.name}" tidak aktif`, 400);

      const amount =
        a.priceMode === 'PERCENT' ? pct(baseTotal, a.price) : Math.round(a.price * it.quantity);

      return {
        optionId: a.id,
        name: a.name,
        priceMode: a.priceMode,
        price: a.price,
        amount,
      };
    });

    const addonsSum = itemAddons.reduce((s, a) => s + a.amount, 0);
    servicesSubtotal += baseTotal;
    addonsTotal += addonsSum;

    return {
      serviceId: service.id,
      serviceName: service.name,
      pricingType: service.pricingType,
      unitPrice: service.price,
      quantity: it.quantity,
      notes: it.notes || null,
      addons: itemAddons,
      lineTotal: baseTotal + addonsSum,
    };
  });

  // Biaya kecepatan
  let speedFee = 0;
  if (speed) {
    speedFee =
      speed.priceMode === 'PERCENT' ? pct(servicesSubtotal, speed.price) : speed.price;
  }

  // Biaya penerimaan
  const deliveryFee = fulfillment ? fulfillment.price : 0;

  const gross = servicesSubtotal + addonsTotal + speedFee + deliveryFee;
  const discount = input.discount || 0;
  if (discount > gross) {
    throw new AppError('Diskon tidak boleh melebihi total sebelum diskon', 400);
  }

  return {
    items,
    speed: speed
      ? { id: speed.id, name: speed.name, fee: speedFee, hours: speed.durationHours }
      : null,
    fulfillment: fulfillment
      ? {
          id: fulfillment.id,
          name: fulfillment.name,
          fee: deliveryFee,
          receiveMethod: detectReceiveMethod(fulfillment.name),
        }
      : null,
    servicesSubtotal,
    addonsTotal,
    speedFee,
    deliveryFee,
    subtotal: servicesSubtotal + addonsTotal,
    discount,
    total: gross - discount,
  };
}

module.exports = { calculate };