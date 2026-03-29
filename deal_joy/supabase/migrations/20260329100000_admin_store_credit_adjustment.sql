-- =============================================================
-- Store Credit：管理员调整类型 + RPC（仅 service_role 执行）
-- =============================================================

-- 1. 扩展流水 type，支持后台人工调整
ALTER TABLE public.store_credit_transactions
  DROP CONSTRAINT IF EXISTS store_credit_transactions_type_check;

ALTER TABLE public.store_credit_transactions
  ADD CONSTRAINT store_credit_transactions_type_check
  CHECK (type IN ('refund_credit', 'purchase_deduction', 'admin_adjustment'));

COMMENT ON CONSTRAINT store_credit_transactions_type_check ON public.store_credit_transactions IS
  'admin_adjustment: 后台调整，amount 为正增加、为负扣减';

-- 2. 管理员调整余额并记流水（delta 正加负减；余额不得为负）
CREATE OR REPLACE FUNCTION public.admin_adjust_store_credit(
  p_user_id uuid,
  p_delta   numeric,
  p_note    text DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new numeric;
BEGIN
  IF p_delta IS NULL THEN
    RAISE EXCEPTION 'p_delta is required';
  END IF;

  IF p_delta = 0 THEN
    SELECT amount INTO v_new FROM public.store_credits WHERE user_id = p_user_id;
    RETURN COALESCE(v_new, 0);
  END IF;

  -- 确保存在一行（余额从 0 开始）
  INSERT INTO public.store_credits (user_id, amount)
  VALUES (p_user_id, 0)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.store_credits
  SET amount = amount + p_delta,
      updated_at = now()
  WHERE user_id = p_user_id
  RETURNING amount INTO v_new;

  IF v_new IS NULL THEN
    RAISE EXCEPTION 'store_credits row missing for user %', p_user_id;
  END IF;

  INSERT INTO public.store_credit_transactions
    (user_id, order_item_id, amount, type, description)
  VALUES
    (
      p_user_id,
      NULL,
      p_delta,
      'admin_adjustment',
      NULLIF(trim(both FROM coalesce(p_note, '')), '')
    );

  RETURN v_new;
END;
$$;

COMMENT ON FUNCTION public.admin_adjust_store_credit(uuid, numeric, text) IS
  'Admin 调整用户 store credit；仅 service_role 可调用。违反 amount>=0 时 UPDATE 失败整段回滚。';

REVOKE ALL ON FUNCTION public.admin_adjust_store_credit(uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_adjust_store_credit(uuid, numeric, text) TO service_role;
