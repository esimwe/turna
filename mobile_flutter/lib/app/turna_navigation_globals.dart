import 'package:flutter/material.dart';

import 'turna_active_chat_registry.dart';

final GlobalKey<NavigatorState> kTurnaNavigatorKey =
    GlobalKey<NavigatorState>();
final RouteObserver<PageRoute<dynamic>> kTurnaRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
final ValueNotifier<AppLifecycleState> kTurnaLifecycleState = ValueNotifier(
  AppLifecycleState.resumed,
);
final TurnaActiveChatRegistry kTurnaActiveChatRegistry =
    TurnaActiveChatRegistry();
