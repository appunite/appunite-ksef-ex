-- Seed default invoice categories from the legacy Swift Category enum.
--
-- Usage:
--   psql $DATABASE_URL -v company_id="'<UUID>'" -f priv/repo/seed_categories.sql
--
-- Idempotent: uses ON CONFLICT to skip existing rows (matched by company_id + name).
-- Safe to re-run on production.

INSERT INTO categories (id, company_id, name, emoji, description, sort_order, inserted_at, updated_at)
VALUES
  -- people (sort_order 100–113)
  (gen_random_uuid(), :company_id, 'people:services',         '🧑‍💼', 'Digital services for the People Team',              100, now(), now()),
  (gen_random_uuid(), :company_id, 'people:benefits',         '🏥', 'Employee benefits and perks',                        101, now(), now()),
  (gen_random_uuid(), :company_id, 'people:supply',           '🛒', 'Office supply expenses',                             102, now(), now()),
  (gen_random_uuid(), :company_id, 'people:transportation',   '🚕', 'Employee transportation costs',                      103, now(), now()),
  (gen_random_uuid(), :company_id, 'people:outings',          '🍹', 'Team-building activities',                           104, now(), now()),
  (gen_random_uuid(), :company_id, 'people:apartments',       '🏘️', 'Employee housing expenses',                          105, now(), now()),
  (gen_random_uuid(), :company_id, 'people:books',            '📚', 'Books and educational materials',                    106, now(), now()),
  (gen_random_uuid(), :company_id, 'people:newsletter',       '🗞️', 'Employee newsletter services and subscriptions',     107, now(), now()),
  (gen_random_uuid(), :company_id, 'people:training',         '📖', 'Employee training programs',                         108, now(), now()),
  (gen_random_uuid(), :company_id, 'people:events',           '🎈', 'Event hosting and attendance',                       109, now(), now()),
  (gen_random_uuid(), :company_id, 'people:employer-branding','💼', 'Company representation at events',                   110, now(), now()),
  (gen_random_uuid(), :company_id, 'people:delivery',         '📦', 'Shipping and delivery expenses',                     111, now(), now()),
  (gen_random_uuid(), :company_id, 'people:patronage',        '🙏', 'Charitable contributions',                           112, now(), now()),
  (gen_random_uuid(), :company_id, 'people:gifts',            '🎁', 'Employee recognition gifts',                         113, now(), now()),

  -- office (sort_order 200–202)
  (gen_random_uuid(), :company_id, 'office:rent-and-administration', '🏢', 'Office leasing costs',               200, now(), now()),
  (gen_random_uuid(), :company_id, 'office:maintenance',             '🛠️', 'Office maintenance and repairs',      201, now(), now()),
  (gen_random_uuid(), :company_id, 'office:equipment',               '🛋️', 'Office equipment purchases',          202, now(), now()),

  -- assets (sort_order 300–302)
  (gen_random_uuid(), :company_id, 'assets:devices',     '💻', 'Company device purchases and maintenance',  300, now(), now()),
  (gen_random_uuid(), :company_id, 'assets:repairs',     '🔧', 'Repairs for company assets',                301, now(), now()),
  (gen_random_uuid(), :company_id, 'assets:accessories', '🎒', 'Accessories for company assets',            302, now(), now()),

  -- operations (sort_order 400–408)
  (gen_random_uuid(), :company_id, 'operations:services',       '⚙️', 'General operational services',                      400, now(), now()),
  (gen_random_uuid(), :company_id, 'operations:essential',      '🔧', 'Essential tools and services for daily operations', 401, now(), now()),
  (gen_random_uuid(), :company_id, 'operations:infrastructure', '🛤️', 'Costs for tech infrastructure maintenance',        402, now(), now()),
  (gen_random_uuid(), :company_id, 'operations:administration', '📋', 'Administrative and legal costs',                   403, now(), now()),
  (gen_random_uuid(), :company_id, 'operations:legal',          '⚖️', 'Legal services and compliance expenses',           404, now(), now()),
  (gen_random_uuid(), :company_id, 'operations:accountancy',    '📊', 'Accounting services and financial management',     405, now(), now()),
  (gen_random_uuid(), :company_id, 'operations:ai',             '🤖', 'AI tools and machine learning services',           406, now(), now()),
  (gen_random_uuid(), :company_id, 'operations:design',         '🎨', 'Design software and creative tools',               407, now(), now()),
  (gen_random_uuid(), :company_id, 'operations:exceptional',    '🌟', 'Specialized and extraordinary services',           408, now(), now()),

  -- recruitment (sort_order 500–501)
  (gen_random_uuid(), :company_id, 'recruitment:services', '🔍', 'Recruitment-related services',  500, now(), now()),
  (gen_random_uuid(), :company_id, 'recruitment:ads',      '📢', 'Job advertisement costs',       501, now(), now()),

  -- marketing (sort_order 600–602)
  (gen_random_uuid(), :company_id, 'marketing:services',    '🎯', 'Marketing support services',       600, now(), now()),
  (gen_random_uuid(), :company_id, 'marketing:ads',         '📈', 'Advertising campaign expenses',    601, now(), now()),
  (gen_random_uuid(), :company_id, 'marketing:conferences', '🌐', 'Conference tickets, fees, and workshops', 602, now(), now()),

  -- sales (sort_order 700–701)
  (gen_random_uuid(), :company_id, 'sales:services',     '💸', 'Sales-related costs',     700, now(), now()),
  (gen_random_uuid(), :company_id, 'sales:direct-sales', '📞', 'Direct sales expenses',   701, now(), now()),

  -- others (sort_order 800–801)
  (gen_random_uuid(), :company_id, 'others:ska-fleet',   '🚗', 'Miscellaneous fleet expenses',      800, now(), now()),
  (gen_random_uuid(), :company_id, 'others:contractors', '🛠️', 'Miscellaneous contractor expenses', 801, now(), now())

ON CONFLICT (company_id, name) DO NOTHING;
