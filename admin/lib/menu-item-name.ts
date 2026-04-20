/**
 * menu_items 名称规范化：与 public.normalize_menu_item_name SQL 一致
 * — trim、去掉最后一个「.」及之后、大小写敏感
 */
export function normalizeMenuItemName(input: string | null | undefined): string {
  if (input == null) return ''
  const t = input.trim()
  if (!t) return ''
  return t.replace(/\.[^.]+$/, '')
}

/** 从上传路径取文件名再规范化（用于 batch 上传） */
export function normalizeMenuItemNameFromFileName(fileName: string): string {
  const base = fileName.split(/[/\\]/).pop() ?? fileName
  return normalizeMenuItemName(base)
}
