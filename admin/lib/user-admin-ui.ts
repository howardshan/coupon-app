/**
 * 后台管理统一视觉：精炼工具风，slate 中性色 + blue 强调。
 * 供用户管理、订单详情侧栏等复用；注释中文；勿使用 'use client'。
 */

/** 侧栏小卡片 */
export const UA_SIDEBAR_CARD =
  'rounded-xl border border-slate-200/90 bg-white p-4 shadow-sm ring-1 ring-slate-900/[0.04]'

/** 主列大卡片 */
export const UA_MAIN_CARD =
  'rounded-2xl border border-slate-200/90 bg-white shadow-sm ring-1 ring-slate-900/[0.04]'

/** 主列大卡片 + 内边距（资料、账单地址等） */
export const UA_MAIN_CARD_PAD = `${UA_MAIN_CARD} p-6 sm:p-8`

/** 资料卡左侧强调条 */
export const UA_PROFILE_ACCENT_BAR = 'border-l-[3px] border-l-blue-600'

/** 区块小标题（英文标签） */
export const UA_SECTION_TITLE =
  'text-[11px] font-semibold uppercase tracking-[0.14em] text-slate-500'

/** 列表页眉标 */
export const UA_PAGE_KICKER =
  'text-[11px] font-semibold uppercase tracking-[0.2em] text-blue-600'

export const UA_PAGE_TITLE = 'text-3xl font-bold tracking-tight text-slate-900'

export const UA_SUBTITLE = 'text-sm text-slate-600'

/** 返回 / 弱按钮 */
export const UA_BACK_BTN =
  'inline-flex items-center gap-2 rounded-xl border border-slate-200/90 bg-white px-3 py-2 text-sm font-medium text-slate-600 shadow-sm ring-1 ring-slate-900/[0.03] transition hover:border-slate-300 hover:bg-slate-50 hover:text-slate-900'

/** 筛选工具栏容器 */
export const UA_FILTER_SHELL =
  'rounded-2xl border border-slate-200/90 bg-white p-5 sm:p-6 shadow-sm ring-1 ring-slate-900/[0.04]'

/** 表单控件 */
export const UA_FIELD =
  'w-full min-w-0 rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-900 shadow-sm outline-none transition placeholder:text-slate-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-500/15'

/** 表格头行 */
export const UA_TABLE_HEAD =
  'border-b border-slate-200 bg-gradient-to-b from-slate-50 to-slate-50/80'

export const UA_TABLE_HEAD_CELL =
  'px-4 py-3.5 text-left text-[11px] font-semibold uppercase tracking-wider text-slate-500'

export const UA_TABLE_ROW = 'transition-colors hover:bg-slate-50/80'

export const UA_TABLE_CELL = 'px-4 py-3.5'

/** 主链接（姓名等） */
export const UA_LINK_PRIMARY =
  'font-semibold text-blue-700 underline decoration-blue-700/30 underline-offset-2 transition hover:text-blue-800 hover:decoration-blue-800/50'

/** 分页 / 小号次要按钮 */
export const UA_PAGE_BTN =
  'rounded-xl border border-slate-200/90 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm ring-1 ring-slate-900/[0.03] transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50'

export const UA_SECONDARY_BTN =
  'rounded-xl border border-slate-200/90 bg-white px-3 py-2 text-sm font-medium text-slate-700 shadow-sm ring-1 ring-slate-900/[0.03] transition hover:bg-slate-50 disabled:opacity-50'

/** 侧栏内全宽小号按钮 */
export const UA_SIDEBAR_ACTION =
  'mt-3 flex w-full items-center justify-center rounded-xl border border-slate-200/90 bg-white px-3 py-2 text-xs font-semibold text-slate-700 shadow-sm ring-1 ring-slate-900/[0.03] transition hover:bg-slate-50 disabled:opacity-50'

/** 弹窗内容容器 */
export const UA_MODAL_SHELL =
  'relative z-[1] flex flex-col overflow-hidden rounded-2xl border border-slate-200/90 bg-white shadow-2xl shadow-slate-900/10 ring-1 ring-slate-900/[0.05]'

export const UA_MODAL_HEADER =
  'flex shrink-0 items-center justify-between gap-3 border-b border-slate-200/90 bg-slate-50/50 px-4 py-3'

export const UA_MODAL_TABLE_HEAD =
  'sticky top-0 z-10 border-b border-slate-200 bg-gradient-to-b from-slate-50 to-white'

export const UA_MODAL_TH =
  'px-2 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wider text-slate-500'
