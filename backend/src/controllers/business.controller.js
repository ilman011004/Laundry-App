const { z } = require('zod');
const prisma = require('../lib/prisma');

const KEYS = ['name', 'address', 'phone'];

const schema = z.object({
  name: z.string().trim().min(1, 'Nama usaha wajib diisi').max(60),
  address: z.string().trim().max(200).default(''),
  phone: z.string().trim().max(30).default(''),
});

async function read() {
  const rows = await prisma.appSetting.findMany({
    where: { key: { in: KEYS.map((k) => `business.${k}`) } },
  });
  const map = Object.fromEntries(rows.map((r) => [r.key.replace('business.', ''), r.value]));
  return { name: map.name || 'Laundry', address: map.address || '', phone: map.phone || '' };
}

async function get(req, res) {
  res.json({ data: await read() });
}

async function update(req, res) {
  const body = schema.parse(req.body);
  await prisma.$transaction(
    KEYS.map((k) =>
      prisma.appSetting.upsert({
        where: { key: `business.${k}` },
        update: { value: body[k] },
        create: { key: `business.${k}`, value: body[k] },
      })
    )
  );
  res.json({ data: await read() });
}

module.exports = { get, update };