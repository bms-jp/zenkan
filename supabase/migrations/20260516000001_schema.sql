-- =============================================================================
-- 01_schema.sql  全テーブル定義
-- kanri-system (zenkan) — 不動産管理システム
-- =============================================================================

-- UUIDv4 拡張
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- organizations (マルチテナント基盤)
-- -----------------------------------------------------------------------------
create table if not exists organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- MASTER DATA
-- -----------------------------------------------------------------------------

-- 家主
create table if not exists owners (
  id              text primary key,            -- フロントエンド生成 ID (own_xxx)
  organization_id uuid references organizations(id) on delete cascade,
  name            text not null,
  kana            text,
  type            text default '個人',         -- 個人 / 法人
  zip             text,
  address         text,
  tel             text,
  fax             text,
  email           text,
  bank            text,
  branch          text,
  account_type    text default '普通',
  account_no      text,
  account_name    text,
  memo            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 建物
create table if not exists buildings (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  name            text not null,
  kana            text,
  owner_id        text references owners(id) on delete restrict,
  zip             text,
  address         text,
  structure       text default 'RC',
  floors          integer,
  total_units     integer,
  built_year      integer,
  built_month     integer,
  parking         text default 'なし',
  memo            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 部屋
create table if not exists rooms (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  building_id     text references buildings(id) on delete restrict,
  room_no         text not null,
  floor           integer,
  layout          text default '1K',
  area            numeric(8,2),
  direction       text default '-',
  status          text default '空室',         -- 入居中 / 空室 / 募集中
  rent            integer,
  fee             integer,
  deposit         integer,
  key_money       integer,
  facilities      text,
  memo            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 契約者
create table if not exists tenants (
  id                  text primary key,
  organization_id     uuid references organizations(id) on delete cascade,
  name                text not null,
  kana                text,
  birthday            date,
  tel                 text,
  email               text,
  occupation          text,
  room_id             text references rooms(id) on delete restrict,
  contract_start      date,
  contract_end        date,
  rent                integer,
  guarantor           text,
  emergency_name      text,
  emergency_relation  text,
  emergency_tel       text,
  memo                text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- 取引業者
create table if not exists vendors (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  name            text not null,
  kana            text,
  category        text default '修繕',
  person          text,
  tel             text,
  fax             text,
  email           text,
  zip             text,
  address         text,
  memo            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- OPERATIONAL DATA
-- -----------------------------------------------------------------------------

-- 申込
create table if not exists applications (
  id                  text primary key,
  organization_id     uuid references organizations(id) on delete cascade,
  applicant_name      text not null,
  applicant_kana      text,
  birthday            date,
  applicant_tel       text,
  applicant_email     text,
  occupation          text,
  annual_income       integer,
  room_id             text references rooms(id) on delete restrict,
  application_date    date not null,
  move_in_wish        date,
  status              text default '申込中',   -- 申込中 / 審査中 / 承認 / 否認
  emergency_name      text,
  emergency_relation  text,
  emergency_tel       text,
  memo                text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- 契約
create table if not exists contracts (
  id                  text primary key,
  organization_id     uuid references organizations(id) on delete cascade,
  contract_no         text not null,
  contract_type       text default '新規',     -- 新規 / 更新
  tenant_name         text not null,
  tenant_kana         text,
  room_id             text references rooms(id) on delete restrict,
  application_id      text references applications(id) on delete set null,
  contract_date       date,
  start_date          date not null,
  end_date            date not null,
  status              text default '契約中',   -- 契約中 / 解約予定 / 解約済
  rent                integer not null,
  fee                 integer default 0,
  deposit             integer default 0,
  key_money           integer default 0,
  renewal_fee         integer default 0,
  guarantor           text,
  guarantor_contact   text,
  cosigner            text,
  cosigner_tel        text,
  memo                text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- 請求
create table if not exists billings (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  contract_id     text references contracts(id) on delete restrict,
  year            integer not null,
  month           integer not null,
  billing_date    date,
  due_date        date,
  rent_amount     integer not null default 0,
  fee_amount      integer not null default 0,
  other_amount    integer not null default 0,
  other_note      text,
  total_amount    integer not null default 0,
  paid_amount     integer not null default 0,
  status          text default '未入金',       -- 未入金 / 一部入金 / 入金済
  memo            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (contract_id, year, month)
);

-- 入金
create table if not exists payments (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  billing_id      text references billings(id) on delete cascade,
  paid_date       date not null,
  amount          integer not null,
  method          text,
  memo            text,
  created_at      timestamptz not null default now()
);

-- 家主送金
create table if not exists remittances (
  id                    text primary key,
  organization_id       uuid references organizations(id) on delete cascade,
  owner_id              text references owners(id) on delete restrict,
  year                  integer not null,
  month                 integer not null,
  total_rent_received   integer not null default 0,
  management_fee        integer not null default 0,
  management_fee_rate   numeric(5,2) default 0,
  repairs               integer not null default 0,
  other_deductions      integer not null default 0,
  other_income          integer not null default 0,
  net_amount            integer not null default 0,
  status                text default '未送金',  -- 未送金 / 送金済
  paid_date             date,
  memo                  text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (owner_id, year, month)
);

-- 業者支払
create table if not exists vendor_payments (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  vendor_id       text references vendors(id) on delete restrict,
  payment_date    date not null,
  purpose         text not null,
  amount          integer not null,
  method          text default '振込',
  status          text default '予定',         -- 予定 / 支払済
  paid_date       date,
  building_id     text references buildings(id) on delete set null,
  memo            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 問い合わせ / チケット
create table if not exists tickets (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  ticket_no       text not null,
  inquiry_date    date not null,
  category        text default '設備不具合',
  priority        text default '中',           -- 高 / 中 / 低
  status          text default '受付',         -- 受付 / 対応中 / 業者手配 / 完了
  assignee        text,
  inquirer_name   text not null,
  inquirer_tel    text,
  inquirer_email  text,
  room_id         text references rooms(id) on delete set null,
  content         text not null,
  response        text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 修繕
create table if not exists repairs (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  ticket_id       text references tickets(id) on delete set null,
  building_id     text references buildings(id) on delete restrict,
  room_id         text references rooms(id) on delete set null,
  vendor_id       text references vendors(id) on delete restrict,
  scheduled_date  date not null,
  completion_date date,
  status          text default '予定',         -- 予定 / 実施中 / 完了
  work_content    text not null,
  cost            integer default 0,
  paid_by         text default '家主負担',      -- 家主負担 / 借主負担 / 管理会社負担
  memo            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 工事案件
create table if not exists constructions (
  id                      text primary key,
  organization_id         uuid references organizations(id) on delete cascade,
  project_no              text not null,
  name                    text not null,
  category                text default '大規模修繕',
  building_id             text references buildings(id) on delete set null,
  owner_id                text references owners(id) on delete set null,
  client_name             text,
  main_vendor_id          text references vendors(id) on delete set null,
  assignee                text,
  status                  text default '見積',  -- 見積 / 受注 / 施工中 / 完了 / 入金済 / キャンセル
  contract_date           date,
  start_date              date,
  end_date                date,
  completion_date         date,
  contract_amount         integer not null default 0,
  billed_amount           integer default 0,
  paid_amount             integer default 0,
  payment_date            date,
  subcontractor_cost      integer default 0,
  subcontractor_paid_date date,
  memo                    text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- 監査ログ
create table if not exists audit_logs (
  id              text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  ts              timestamptz not null default now(),
  action          text not null,
  entity          text not null,
  summary         text,
  user_id         uuid
);

-- システム設定 (組織ごとに1行)
create table if not exists settings (
  organization_id         uuid primary key references organizations(id) on delete cascade,
  company_name            text,
  default_due_day         integer default 27,
  management_fee_rate     numeric(5,2) default 5,
  ai_enabled              boolean default false,
  ai_endpoint             text,
  ai_api_key_encrypted    text,
  ai_model                text default 'claude-sonnet-4-6',
  ai_auth_mode            text default 'gateway',
  ai_max_tokens           integer default 4096,
  extra                   jsonb default '{}',
  updated_at              timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- インデックス
-- -----------------------------------------------------------------------------
create index if not exists idx_buildings_owner      on buildings(owner_id);
create index if not exists idx_rooms_building       on rooms(building_id);
create index if not exists idx_tenants_room         on tenants(room_id);
create index if not exists idx_applications_room    on applications(room_id);
create index if not exists idx_contracts_room       on contracts(room_id);
create index if not exists idx_billings_contract    on billings(contract_id);
create index if not exists idx_billings_ym          on billings(year, month);
create index if not exists idx_payments_billing     on payments(billing_id);
create index if not exists idx_remittances_owner    on remittances(owner_id);
create index if not exists idx_vendor_payments_vnd  on vendor_payments(vendor_id);
create index if not exists idx_tickets_room         on tickets(room_id);
create index if not exists idx_repairs_building     on repairs(building_id);
create index if not exists idx_repairs_vendor       on repairs(vendor_id);
create index if not exists idx_audit_logs_ts        on audit_logs(ts desc);
-- org-scoped indexes (multi-tenancy)
create index if not exists idx_owners_org           on owners(organization_id);
create index if not exists idx_buildings_org        on buildings(organization_id);
create index if not exists idx_rooms_org            on rooms(organization_id);
create index if not exists idx_tenants_org          on tenants(organization_id);
create index if not exists idx_vendors_org          on vendors(organization_id);
create index if not exists idx_contracts_org        on contracts(organization_id);
create index if not exists idx_billings_org         on billings(organization_id);
create index if not exists idx_payments_org         on payments(organization_id);
create index if not exists idx_remittances_org      on remittances(organization_id);
