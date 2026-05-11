-- ============================================
-- Seed de las 14 mesas con tokens HMAC
-- Secret HMAC usado: guardado fuera del repo (necesario solo para regenerar tokens)
-- ============================================

insert into mesas (id, token, activa) values
  (1, 'vz2azskjxq63', true),
  (2, 'ekp3c4o2qur2', true),
  (3, 'skhhnemdavfv', true),
  (4, 'qk3ssjgmefzj', true),
  (5, 'b3beo7kf36rp', true),
  (6, 'kfcb2lqcw7pr', true),
  (7, 'xu65nqjywhr7', true),
  (8, '5pffa77kt56z', true),
  (9, 's6vxtio2wbqs', true),
  (10, 'nrzd2iu2k2fd', true),
  (11, 't6ijefdyhe4b', true),
  (12, 'aumqwbw6cefd', true),
  (13, 'sqkvlifvoep4', true),
  (14, 'fttxfabyt2fd', true)
on conflict (id) do update set token = excluded.token;

-- Config inicial
insert into config (clave, valor) values
  ('horario', '{"abierto": true, "apertura": "13:00", "cierre": "23:30"}'::jsonb),
  ('iva', '{"incluido": true, "porcentaje": 10}'::jsonb),
  ('mensaje_cerrado', '"Estamos cerrados ahora mismo. Te esperamos pronto."'::jsonb)
on conflict (clave) do nothing;
