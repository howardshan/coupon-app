-- 新增 RPC：为已存在的 coupon 重新生成 qr_code 和 coupon_code
-- 用途：当 gifted 状态被赠送人 recall 后，原来的 code 可能已经被受赠人看到
--      为安全起见重新生成，让已泄露的码失效

CREATE OR REPLACE FUNCTION public.regenerate_coupon_codes(p_coupon_id uuid)
RETURNS TABLE (
  qr_code     text,
  coupon_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_new_qr   text;
  v_new_code text;
BEGIN
  -- 生成唯一 16 位数字 QR（复用现有生成函数）
  v_new_qr := public.generate_qr_code_16_numeric();

  -- 生成唯一 16 位大写十六进制 coupon_code（与 order_item_triggers 保持一致）
  LOOP
    v_new_code := UPPER(SUBSTRING(REPLACE(gen_random_uuid()::text, '-', ''), 1, 16));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.coupons WHERE coupon_code = v_new_code);
  END LOOP;

  -- 原子更新 coupons 表
  UPDATE public.coupons
  SET qr_code = v_new_qr,
      coupon_code = v_new_code,
      updated_at = now()
  WHERE id = p_coupon_id;

  RETURN QUERY SELECT v_new_qr, v_new_code;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.regenerate_coupon_codes(uuid)
  TO service_role;

COMMENT ON FUNCTION public.regenerate_coupon_codes(uuid) IS
  '重新生成 coupon 的 qr_code 和 coupon_code（带唯一性检查）。用于 gift recall 等需要让旧 code 失效的场景。仅允许 service_role 调用。';
