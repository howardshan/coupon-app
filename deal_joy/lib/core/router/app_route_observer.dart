import 'package:flutter/material.dart';

/// 根导航 [RouteObserver]：订单详情 / 售后时间线等页通过 [RouteAware.didPopNext] 在上层路由 pop 后刷新售后数据
final appRouteObserver = RouteObserver<PageRoute<dynamic>>();
