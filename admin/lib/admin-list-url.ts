/**
 * 后台列表页：在现有 query 上合并筛选/搜索更新，并重置到第 1 页（可关闭）。
 */
export function buildAdminListUrl(
  pathname: string,
  params: URLSearchParams,
  updates: Record<string, string | number | undefined | string[]>,
  options?: { resetPage?: boolean }
): string {
  const next = new URLSearchParams(params)
  for (const [key, val] of Object.entries(updates)) {
    if (val === undefined || val === '') {
      next.delete(key)
    } else if (Array.isArray(val)) {
      next.delete(key)
      val.forEach((v) => next.append(key, v))
    } else {
      next.set(key, String(val))
    }
  }
  if (options?.resetPage !== false) {
    next.delete('page')
    next.set('page', '1')
  }
  const qs = next.toString()
  return qs ? `${pathname}?${qs}` : pathname
}

/** 仅翻页，不改其它 query */
export function buildAdminListUrlPage(pathname: string, params: URLSearchParams, page: number): string {
  const next = new URLSearchParams(params)
  next.set('page', String(Math.max(1, page)))
  return `${pathname}?${next.toString()}`
}
