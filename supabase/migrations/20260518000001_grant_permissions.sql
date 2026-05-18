-- =============================================================================
-- 05_grant_permissions.sql  テーブル権限付与
-- 既存マイグレーションに GRANT が含まれていなかったため、
-- authenticated / anon ロールへのアクセス権を追加する。
-- RLS ポリシーは 02_rls.sql で設定済み（organization_id スコープ）。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- authenticated ロール（ログイン済みユーザー）
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- -----------------------------------------------------------------------------
-- anon ロール（未ログイン / Supabase anon key 使用時）
-- RLS ポリシーが auth.uid() を要求するため、実質的にデータへのアクセスは不可。
-- ただし PostgREST が権限チェックを先に行うため GRANT 自体は必要。
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;

-- -----------------------------------------------------------------------------
-- create_organization() 関数の実行権限
-- 初回ログイン時に新規組織を作成するため authenticated から呼び出す。
-- -----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION create_organization(text) TO authenticated;
GRANT EXECUTE ON FUNCTION my_organization_ids() TO authenticated;

-- -----------------------------------------------------------------------------
-- 確認メッセージ
-- -----------------------------------------------------------------------------
DO $$ BEGIN
  RAISE NOTICE 'grant_permissions applied: authenticated/anon can now access all public tables.';
END $$;
