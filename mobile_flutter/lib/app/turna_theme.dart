import 'package:flutter/material.dart';

class TurnaColors {
  static const primary50 = Color(0xFFEEF7FF);
  static const primary100 = Color(0xFFD9EEFF);
  static const primary200 = Color(0xFFBCE0FF);
  static const primary300 = Color(0xFF8FCBFF);
  static const primary400 = Color(0xFF5BB0FF);
  static const primary = Color(0xFF2F80ED);
  static const primaryStrong = Color(0xFF1F6FEB);
  static const primaryDeep = Color(0xFF1B4ED8);
  static const primary800 = Color(0xFF163EA8);
  static const primary900 = Color(0xFF132F7D);
  static const accent100 = Color(0xFFDFF8FF);
  static const accent200 = Color(0xFFB8EFFF);
  static const accent300 = Color(0xFF7FE2FF);
  static const accent = Color(0xFF38BDF8);
  static const accentStrong = Color(0xFF00C2FF);
  static const accentDeep = Color(0xFF00A7DF);
  static const navy700 = Color(0xFF14213D);
  static const navy800 = Color(0xFF0F172A);
  static const navy900 = Color(0xFF0B1220);

  static const background = Color(0xFFFFFFFF);
  static const backgroundSoft = Color(0xFFF7F9FC);
  static const backgroundMuted = Color(0xFFEEF4FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHover = Color(0xFFF3F8FF);
  static const border = Color(0xFFD8E6F5);
  static const divider = Color(0xFFE2ECF7);

  static const text = Color(0xFF0F172A);
  static const textSoft = Color(0xFF334155);
  static const textMuted = Color(0xFF64748B);
  static const textInverse = Color(0xFFFFFFFF);

  static const chatOutgoing = Color(0xFFE2FFC8);
  static const chatOutgoingText = Color(0xFF23291B);
  static const chatOutgoingMeta = Color(0xFF88A274);
  static const chatOutgoingRead = Color(0xFF1D89F8);
  static const chatIncoming = Color(0xFFEDF4FB);
  static const chatIncomingText = Color(0xFF0F172A);
  static const chatUnreadBg = Color(0xFFEEF7FF);
  static const chatActive = Color(0xFF38BDF8);

  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF38BDF8);

  static const avatarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary300, primary],
  );
  static const chatOutgoingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [chatOutgoing, chatOutgoing],
  );
  static const shadowBubble = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 3,
    offset: Offset(0, 1),
  );
  static const shadowSoft = BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );
  static const shadowFab = BoxShadow(
    color: Color(0x402F80ED),
    blurRadius: 20,
    offset: Offset(0, 8),
  );
}

class TurnaChatTokens {
  static const bubbleRadius = 20.0;
  static const bubbleRadiusTail = 8.0;
  static const messageMaxWidthFactor = 0.76;
  static const stackGap = 4.0;
  static const groupGap = 10.0;
  static const sectionGap = 14.0;
  static const dateGap = 18.0;
}
