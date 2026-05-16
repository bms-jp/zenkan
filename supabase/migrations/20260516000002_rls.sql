-- =============================================================================
-- 02_rls.sql  Row Level Security ポリシー
-- 全テーブルを organization_id でスコープし、
-- auth.uid() を members テーブル経由でチェックする。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- members (ユーザー ↔ 組織 の紐付け)
-- -----------------------------------------------------------------------------
create table if not exists members (
  user_id         uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  role            text not null default 'member',  -- owner / admin / member
  created_at      timestamptz not null default now(),
  primary key (user_id, organization_id)
);

create index if not exists idx_members_org  on members(organization_id);
create index if not exists idx_members_user on members(user_id);

-- -----------------------------------------------------------------------------
-- ヘルパー関数
-- -----------------------------------------------------------------------------
create or replace function my_organization_ids()
returns setof uuid language sql security definer stable as $$
  select organization_id from members where user_id = auth.uid()
$$;

-- -----------------------------------------------------------------------------
-- RLS を有効化
-- -----------------------------------------------------------------------------
alter table organizations   enable row level security;
alter table members         enable row level security;
alter table owners          enable row level security;
alter table buildings       enable row level security;
alter table rooms           enable row level security;
alter table tenants         enable row level security;
alter table vendors         enable row level security;
alter table applications    enable row level security;
alter table contracts       enable row level security;
alter table billings        enable row level security;
alter table payments        enable row level security;
alter table remittances     enable row level security;
alter table vendor_payments enable row level security;
alter table tickets         enable row level security;
alter table repairs         enable row level security;
alter table constructions   enable row level security;
alter table audit_logs      enable row level security;
alter table settings        enable row level security;

-- -----------------------------------------------------------------------------
-- organizations ポリシー
-- -----------------------------------------------------------------------------
create policy "organizations: 所属メンバーのみ参照"
  on organizations for select
  using (id in (select my_organization_ids()));

create policy "organizations: 所属メンバーのみ更新"
  on organizations for update
  using (id in (select my_organization_ids()));

-- -----------------------------------------------------------------------------
-- members ポリシー
-- -----------------------------------------------------------------------------
create policy "members: 自分のレコードを参照"
  on members for select
  using (user_id = auth.uid()
      or organization_id in (select my_organization_ids()));

create policy "members: 管理者のみ追加"
  on members for insert
  with check (
    organization_id in (
      select organization_id from members
      where user_id = auth.uid() and role in ('owner','admin')
    )
  );

create policy "members: 管理者のみ削除"
  on members for delete
  using (
    organization_id in (
      select organization_id from members
      where user_id = auth.uid() and role in ('owner','admin')
    )
  );

-- -----------------------------------------------------------------------------
-- 汎用マクロ: 各テーブルに CRUD ポリシーを付与
-- organization_id カラムがあるテーブルすべてに適用
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
  tables text[] := array[
    'owners','buildings','rooms','tenants','vendors',
    'applications','contracts','billings','payments',
    'remittances','vendor_payments','tickets','repairs',
    'constructions','audit_logs'
  ];
begin
  foreach t in array tables loop
    -- SELECT
    execute format(
      'create policy %I on %I for select using (organization_id in (select my_organization_ids()))',
      t || ': 組織メンバーのみ参照', t
    );
    -- INSERT
    execute format(
      'create policy %I on %I for insert with check (organization_id in (select my_organization_ids()))',
      t || ': 組織メンバーのみ作成', t
    );
    -- UPDATE
    execute format(
      'create policy %I on %I for update using (organization_id in (select my_organization_ids()))',
      t || ': 組織メンバーのみ更新', t
    );
    -- DELETE
    execute format(
      'create policy %I on %I for delete using (organization_id in (select my_organization_ids()))',
      t || ': 組織メンバーのみ削除', t
    );
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- settings ポリシー (organization_id が PK のため個別定義)
-- -----------------------------------------------------------------------------
create policy "settings: 参照"
  on settings for select
  using (organization_id in (select my_organization_ids()));

create policy "settings: 更新(管理者のみ)"
  on settings for update
  using (
    organization_id in (
      select organization_id from members
      where user_id = auth.uid() and role in ('owner','admin')
    )
  );

create policy "settings: 作成(管理者のみ)"
  on settings for insert
  with check (
    organization_id in (
      select organization_id from members
      where user_id = auth.uid() and role in ('owner','admin')
    )
  );
