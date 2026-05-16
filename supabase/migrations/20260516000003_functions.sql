-- =============================================================================
-- 03_functions.sql  ビジネスロジック関数
-- =============================================================================

-- -----------------------------------------------------------------------------
-- updated_at 自動更新トリガー
-- -----------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare
  t text;
  tables text[] := array[
    'owners','buildings','rooms','tenants','vendors',
    'applications','contracts','billings','remittances',
    'vendor_payments','tickets','repairs','constructions'
  ];
begin
  foreach t in array tables loop
    execute format(
      'create trigger trg_%s_updated_at before update on %I
       for each row execute function set_updated_at()',
      t, t
    );
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 請求一括生成
-- 対象月の「契約中」「解約予定」契約に対してまだ請求がなければ生成する
-- -----------------------------------------------------------------------------
create or replace function generate_billings(
  p_organization_id uuid,
  p_year   integer,
  p_month  integer,
  p_due_day integer default 27
)
returns integer  -- 生成件数
language plpgsql security definer as $$
declare
  v_count  integer := 0;
  v_due    text;
  rec      record;
  v_id     text;
begin
  v_due := format('%s-%s-%s', p_year,
    lpad(p_month::text, 2, '0'),
    lpad(p_due_day::text, 2, '0'));

  for rec in
    select c.id, c.rent, c.fee
    from contracts c
    where c.organization_id = p_organization_id
      and c.status in ('契約中','解約予定')
      and not exists (
        select 1 from billings b
        where b.contract_id = c.id
          and b.year = p_year and b.month = p_month
      )
  loop
    v_id := 'bil_' || encode(gen_random_bytes(8), 'hex');
    insert into billings (
      id, organization_id, contract_id, year, month,
      billing_date, due_date,
      rent_amount, fee_amount, other_amount, total_amount,
      paid_amount, status
    ) values (
      v_id, p_organization_id, rec.id, p_year, p_month,
      (format('%s-%s-01', p_year, lpad(p_month::text, 2, '0')))::date,
      v_due::date,
      coalesce(rec.rent, 0),
      coalesce(rec.fee, 0),
      0,
      coalesce(rec.rent, 0) + coalesce(rec.fee, 0),
      0, '未入金'
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

-- -----------------------------------------------------------------------------
-- 入金記録
-- billings.paid_amount を更新し、ステータスを自動判定する
-- -----------------------------------------------------------------------------
create or replace function record_payment(
  p_organization_id uuid,
  p_billing_id      text,
  p_paid_date       date,
  p_amount          integer,
  p_method          text default null
)
returns text  -- 作成した payment.id
language plpgsql security definer as $$
declare
  v_pay_id     text;
  v_new_paid   integer;
  v_total      integer;
  v_new_status text;
begin
  select total_amount, paid_amount
  into   v_total, v_new_paid
  from   billings
  where  id = p_billing_id
    and  organization_id = p_organization_id
  for update;

  if not found then
    raise exception '請求が見つかりません: %', p_billing_id;
  end if;

  v_new_paid := v_new_paid + p_amount;
  v_new_status := case
    when v_new_paid <= 0        then '未入金'
    when v_new_paid >= v_total  then '入金済'
    else '一部入金'
  end;

  update billings
  set paid_amount = v_new_paid, status = v_new_status
  where id = p_billing_id;

  v_pay_id := 'pay_' || encode(gen_random_bytes(8), 'hex');
  insert into payments (id, organization_id, billing_id, paid_date, amount, method)
  values (v_pay_id, p_organization_id, p_billing_id, p_paid_date, p_amount, p_method);

  return v_pay_id;
end $$;

-- -----------------------------------------------------------------------------
-- 家主送金一括生成
-- 対象月の請求入金をもとに送金レコードを生成する
-- -----------------------------------------------------------------------------
create or replace function generate_remittances(
  p_organization_id uuid,
  p_year            integer,
  p_month           integer
)
returns integer
language plpgsql security definer as $$
declare
  v_count         integer := 0;
  v_fee_rate      numeric;
  v_month_start   date;
  v_month_end     date;
  rec             record;
  v_id            text;
  v_total_rent    integer;
  v_mgmt_fee      integer;
  v_repairs_cost  integer;
  v_net           integer;
begin
  select management_fee_rate into v_fee_rate
  from settings where organization_id = p_organization_id;
  v_fee_rate := coalesce(v_fee_rate, 5);

  v_month_start := (format('%s-%s-01', p_year, lpad(p_month::text,2,'0')))::date;
  v_month_end   := (v_month_start + interval '1 month - 1 day')::date;

  for rec in
    select o.id as owner_id
    from owners o
    where o.organization_id = p_organization_id
      and not exists (
        select 1 from remittances r
        where r.owner_id = o.id
          and r.year = p_year and r.month = p_month
      )
      and exists (
        select 1 from buildings b where b.owner_id = o.id and b.organization_id = p_organization_id
      )
  loop
    -- 入金合計
    select coalesce(sum(b.paid_amount), 0) into v_total_rent
    from billings b
    join contracts c on c.id = b.contract_id
    join rooms r     on r.id = c.room_id
    join buildings bg on bg.id = r.building_id
    where bg.owner_id = rec.owner_id
      and b.year = p_year and b.month = p_month;

    -- 家主負担修繕費
    select coalesce(sum(rp.cost), 0) into v_repairs_cost
    from repairs rp
    join buildings bg on bg.id = rp.building_id
    where bg.owner_id = rec.owner_id
      and rp.paid_by = '家主負担'
      and rp.completion_date between v_month_start and v_month_end;

    v_mgmt_fee := round(v_total_rent * v_fee_rate / 100);
    v_net      := v_total_rent - v_mgmt_fee - v_repairs_cost;

    v_id := 'rmt_' || encode(gen_random_bytes(8), 'hex');
    insert into remittances (
      id, organization_id, owner_id, year, month,
      total_rent_received, management_fee, management_fee_rate,
      repairs, other_deductions, other_income, net_amount, status
    ) values (
      v_id, p_organization_id, rec.owner_id, p_year, p_month,
      v_total_rent, v_mgmt_fee, v_fee_rate,
      v_repairs_cost, 0, 0, v_net, '未送金'
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

-- -----------------------------------------------------------------------------
-- ダッシュボード集計 (単一 JSON で返す)
-- -----------------------------------------------------------------------------
create or replace function dashboard_summary(p_organization_id uuid)
returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'ownerCount',        (select count(*) from owners      where organization_id = p_organization_id),
    'buildingCount',     (select count(*) from buildings   where organization_id = p_organization_id),
    'roomCount',         (select count(*) from rooms        where organization_id = p_organization_id),
    'occupiedCount',     (select count(*) from rooms        where organization_id = p_organization_id and status = '入居中'),
    'vacantCount',       (select count(*) from rooms        where organization_id = p_organization_id and status = '空室'),
    'activeContracts',   (select count(*) from contracts   where organization_id = p_organization_id and status = '契約中'),
    'unpaidBillings',    (select count(*) from billings    where organization_id = p_organization_id and status in ('未入金','一部入金')),
    'unpaidTotal',       (select coalesce(sum(total_amount - paid_amount),0) from billings where organization_id = p_organization_id and status in ('未入金','一部入金')),
    'openTickets',       (select count(*) from tickets     where organization_id = p_organization_id and status != '完了'),
    'pendingRepairs',    (select count(*) from repairs     where organization_id = p_organization_id and status != '完了')
  )
$$;
