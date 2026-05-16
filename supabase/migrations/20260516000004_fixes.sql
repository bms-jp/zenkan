-- =============================================================================
-- 04_fixes.sql  セキュリティ強化・制約追加
-- =============================================================================

-- -----------------------------------------------------------------------------
-- CHECK 制約
-- -----------------------------------------------------------------------------

-- 部屋ステータス
alter table rooms add constraint chk_room_status
  check (status in ('入居中','空室','募集中'));

-- 申込ステータス
alter table applications add constraint chk_app_status
  check (status in ('申込中','審査中','承認','否認'));

-- 契約ステータス
alter table contracts add constraint chk_contract_status
  check (status in ('契約中','解約予定','解約済'));

-- 請求ステータス
alter table billings add constraint chk_billing_status
  check (status in ('未入金','一部入金','入金済'));

-- 送金ステータス
alter table remittances add constraint chk_remittance_status
  check (status in ('未送金','送金済'));

-- 業者支払ステータス
alter table vendor_payments add constraint chk_vpay_status
  check (status in ('予定','支払済'));

-- チケット優先度
alter table tickets add constraint chk_ticket_priority
  check (priority in ('高','中','低'));

-- チケットステータス
alter table tickets add constraint chk_ticket_status
  check (status in ('受付','対応中','業者手配','完了'));

-- 修繕ステータス
alter table repairs add constraint chk_repair_status
  check (status in ('予定','実施中','完了'));

-- 工事ステータス
alter table constructions add constraint chk_construction_status
  check (status in ('見積','受注','施工中','完了','入金済','キャンセル'));

-- 金額は 0 以上
alter table billings add constraint chk_billing_amounts
  check (rent_amount >= 0 and fee_amount >= 0 and other_amount >= 0
         and total_amount >= 0 and paid_amount >= 0);

alter table payments add constraint chk_payment_amount
  check (amount > 0);

alter table remittances add constraint chk_remittance_amounts
  check (total_rent_received >= 0 and management_fee >= 0
         and repairs >= 0 and other_deductions >= 0 and other_income >= 0);

-- 月は 1-12
alter table billings     add constraint chk_billing_month    check (month between 1 and 12);
alter table remittances  add constraint chk_remittance_month check (month between 1 and 12);

-- 管理費率は 0-100%
alter table settings add constraint chk_fee_rate
  check (management_fee_rate between 0 and 100);

-- members ロール
alter table members add constraint chk_member_role
  check (role in ('owner','admin','member'));

-- -----------------------------------------------------------------------------
-- 監査ログを append-only にする (UPDATE / DELETE 禁止)
-- -----------------------------------------------------------------------------
create or replace rule no_update_audit_logs as
  on update to audit_logs do instead nothing;

create or replace rule no_delete_audit_logs as
  on delete to audit_logs do instead nothing;

-- -----------------------------------------------------------------------------
-- 初回組織セットアップ用関数
-- 新規ユーザーが最初に呼ぶ: 組織と自分の member レコードを同一トランザクションで作成
-- -----------------------------------------------------------------------------
create or replace function create_organization(p_name text)
returns uuid language plpgsql security definer as $$
declare
  v_org_id uuid;
begin
  insert into organizations (name) values (p_name) returning id into v_org_id;
  insert into members (user_id, organization_id, role) values (auth.uid(), v_org_id, 'owner');
  insert into settings (organization_id) values (v_org_id);
  return v_org_id;
end $$;

-- -----------------------------------------------------------------------------
-- IndexedDB → Supabase 一括インポート用関数
-- JSON blob (フロントエンドの data オブジェクト) をそのまま受け取り、
-- 各テーブルに upsert する。
-- 呼び出し: select import_from_indexeddb('{...}'::jsonb, '<org-id>');
-- -----------------------------------------------------------------------------
create or replace function import_from_indexeddb(
  p_data          jsonb,
  p_organization_id uuid
)
returns jsonb language plpgsql security definer as $$
declare
  v_counts jsonb := '{}';
  rec      jsonb;
  v_n      integer;
begin
  -- owners
  v_n := 0;
  for rec in select * from jsonb_array_elements(p_data->'owner') loop
    insert into owners (
      id, organization_id, name, kana, type, zip, address, tel, fax, email,
      bank, branch, account_type, account_no, account_name, memo
    ) values (
      rec->>'id', p_organization_id,
      rec->>'name', rec->>'kana', coalesce(rec->>'type','個人'),
      rec->>'zip', rec->>'address', rec->>'tel', rec->>'fax', rec->>'email',
      rec->>'bank', rec->>'branch', coalesce(rec->>'accountType','普通'),
      rec->>'accountNo', rec->>'accountName', rec->>'memo'
    ) on conflict (id) do update set
      name = excluded.name, kana = excluded.kana,
      zip = excluded.zip, address = excluded.address,
      tel = excluded.tel, email = excluded.email, memo = excluded.memo;
    v_n := v_n + 1;
  end loop;
  v_counts := v_counts || jsonb_build_object('owners', v_n);

  -- buildings
  v_n := 0;
  for rec in select * from jsonb_array_elements(p_data->'building') loop
    insert into buildings (
      id, organization_id, name, kana, owner_id, zip, address,
      structure, floors, total_units, built_year, built_month, parking, memo
    ) values (
      rec->>'id', p_organization_id,
      rec->>'name', rec->>'kana', rec->>'ownerId',
      rec->>'zip', rec->>'address',
      coalesce(rec->>'structure','RC'),
      (rec->>'floors')::integer, (rec->>'totalUnits')::integer,
      (rec->>'builtYear')::integer, (rec->>'builtMonth')::integer,
      coalesce(rec->>'parking','なし'), rec->>'memo'
    ) on conflict (id) do update set
      name = excluded.name, address = excluded.address, memo = excluded.memo;
    v_n := v_n + 1;
  end loop;
  v_counts := v_counts || jsonb_build_object('buildings', v_n);

  -- rooms
  v_n := 0;
  for rec in select * from jsonb_array_elements(p_data->'room') loop
    insert into rooms (
      id, organization_id, building_id, room_no, floor, layout, area,
      direction, status, rent, fee, deposit, key_money, facilities, memo
    ) values (
      rec->>'id', p_organization_id,
      rec->>'buildingId', rec->>'roomNo', (rec->>'floor')::integer,
      coalesce(rec->>'layout','1K'), (rec->>'area')::numeric,
      coalesce(rec->>'direction','-'), coalesce(rec->>'status','空室'),
      (rec->>'rent')::integer, (rec->>'fee')::integer,
      (rec->>'deposit')::integer, (rec->>'keyMoney')::integer,
      rec->>'facilities', rec->>'memo'
    ) on conflict (id) do update set
      status = excluded.status, rent = excluded.rent, memo = excluded.memo;
    v_n := v_n + 1;
  end loop;
  v_counts := v_counts || jsonb_build_object('rooms', v_n);

  -- contracts
  v_n := 0;
  for rec in select * from jsonb_array_elements(p_data->'contract') loop
    insert into contracts (
      id, organization_id, contract_no, contract_type, tenant_name, tenant_kana,
      room_id, contract_date, start_date, end_date, status,
      rent, fee, deposit, key_money, renewal_fee,
      guarantor, guarantor_contact, cosigner, cosigner_tel, memo
    ) values (
      rec->>'id', p_organization_id,
      rec->>'contractNo', coalesce(rec->>'contractType','新規'),
      rec->>'tenantName', rec->>'tenantKana',
      rec->>'roomId',
      (rec->>'contractDate')::date,
      (rec->>'startDate')::date,
      (rec->>'endDate')::date,
      coalesce(rec->>'status','契約中'),
      coalesce((rec->>'rent')::integer, 0),
      coalesce((rec->>'fee')::integer, 0),
      coalesce((rec->>'deposit')::integer, 0),
      coalesce((rec->>'keyMoney')::integer, 0),
      coalesce((rec->>'renewalFee')::integer, 0),
      rec->>'guarantor', rec->>'guarantorContact',
      rec->>'cosigner', rec->>'cosignerTel', rec->>'memo'
    ) on conflict (id) do update set
      status = excluded.status, memo = excluded.memo;
    v_n := v_n + 1;
  end loop;
  v_counts := v_counts || jsonb_build_object('contracts', v_n);

  -- billings
  v_n := 0;
  for rec in select * from jsonb_array_elements(p_data->'billing') loop
    insert into billings (
      id, organization_id, contract_id, year, month,
      billing_date, due_date, rent_amount, fee_amount, other_amount, other_note,
      total_amount, paid_amount, status, memo
    ) values (
      rec->>'id', p_organization_id,
      rec->>'contractId',
      (rec->>'year')::integer, (rec->>'month')::integer,
      (rec->>'billingDate')::date, (rec->>'dueDate')::date,
      coalesce((rec->>'rentAmount')::integer, 0),
      coalesce((rec->>'feeAmount')::integer, 0),
      coalesce((rec->>'otherAmount')::integer, 0),
      rec->>'otherNote',
      coalesce((rec->>'totalAmount')::integer, 0),
      coalesce((rec->>'paidAmount')::integer, 0),
      coalesce(rec->>'status','未入金'), rec->>'memo'
    ) on conflict (id) do update set
      paid_amount = excluded.paid_amount, status = excluded.status;
    v_n := v_n + 1;
  end loop;
  v_counts := v_counts || jsonb_build_object('billings', v_n);

  -- payments
  v_n := 0;
  for rec in select * from jsonb_array_elements(p_data->'payment') loop
    insert into payments (id, organization_id, billing_id, paid_date, amount, method, memo)
    values (
      rec->>'id', p_organization_id,
      rec->>'billingId', (rec->>'paidDate')::date,
      (rec->>'amount')::integer, rec->>'method', rec->>'memo'
    ) on conflict (id) do nothing;
    v_n := v_n + 1;
  end loop;
  v_counts := v_counts || jsonb_build_object('payments', v_n);

  return v_counts;
end $$;

-- -----------------------------------------------------------------------------
-- 完了メッセージ
-- -----------------------------------------------------------------------------
do $$ begin
  raise notice 'zenkan schema v1 applied successfully.';
end $$;
