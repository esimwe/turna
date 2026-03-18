import 'dart:convert';

class TurnaApiException implements Exception {
  TurnaApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TurnaUnauthorizedException extends TurnaApiException {
  TurnaUnauthorizedException([super.message = 'Oturumun suresi doldu.']);
}

String turnaExtractApiErrorMessage(String body, int statusCode) {
  try {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final error = map['error']?.toString();
    switch (error) {
      case 'phone_already_in_use':
        return 'Bu telefon başka bir hesapta kullanılıyor.';
      case 'phone_change_requires_verification':
        return 'Numara değişikliği için doğrulama gerekiyor.';
      case 'email_already_in_use':
        return 'Bu email başka bir hesapta kullanılıyor.';
      case 'username_already_in_use':
        return 'Bu kullanıcı adı başka bir hesapta kullanılıyor.';
      case 'username_change_rate_limited':
        return 'Kullanıcı adını 14 günde en fazla 2 kez değiştirebilirsin.';
      case 'invalid_username':
        return 'Kullanıcı adı uygun değil.';
      case 'validation_error':
        return 'Girilen bilgiler geçersiz.';
      case 'user_not_found':
        return 'Kullanıcı bulunamadı.';
      case 'phone_required':
        return 'Telefon numarası gerekli.';
      case 'invalid_phone':
        return 'Geçerli bir telefon numarası gir.';
      case 'invalid_otp_code':
        return 'Kod 6 haneli olmalı.';
      case 'otp_cooldown':
        return 'Lütfen biraz bekleyip tekrar dene.';
      case 'otp_rate_limited':
        return 'Çok fazla deneme yapıldı. Daha sonra tekrar dene.';
      case 'otp_invalid':
        return 'Kod hatalı. Yeniden dene.';
      case 'otp_expired':
        return 'Kodun suresi doldu. Yeni kod iste.';
      case 'otp_attempts_exceeded':
        return 'Çok fazla hatalı deneme yapıldı. Yeni kod iste.';
      case 'otp_not_found':
        return 'Doğrulama kodu bulunamadı. Yeni kod iste.';
      case 'otp_temporarily_unavailable':
      case 'login_temporarily_unavailable':
      case 'signup_temporarily_unavailable':
        return 'Doğrulama şu an kullanılamıyor.';
      case 'storage_not_configured':
        return 'Dosya depolama servisi hazır değil.';
      case 'invalid_avatar_key':
        return 'Avatar yüklemesi doğrulanamadı.';
      case 'invalid_attachment_key':
        return 'Medya yüklemesi doğrulanamadı.';
      case 'message_not_found':
        return 'Mesaj bulunamadı.';
      case 'message_delete_not_allowed':
        return 'Bu mesaj sadece gönderen tarafından herkesten silinebilir.';
      case 'message_delete_window_expired':
        return 'Mesaj artık herkesten silinemez. 10 dakika sınırı doldu.';
      case 'message_edit_not_allowed':
        return 'Bu mesaj artık düzenlenemez.';
      case 'message_edit_window_expired':
        return 'Mesaj düzenleme süresi doldu. 10 dakika sınırı doldu.';
      case 'message_edit_text_required':
        return 'Düzenlenecek mesaj boş olamaz.';
      case 'message_reaction_not_allowed':
        return 'Bu mesaja tepki eklenemez.';
      case 'chat_search_query_required':
        return 'Arama için bir metin gir.';
      case 'chat_folder_limit_reached':
        return 'En fazla 3 kategori oluşturabilirsin.';
      case 'chat_folder_exists':
        return 'Bu kategori adı zaten kullanılıyor.';
      case 'chat_folder_not_found':
        return 'Kategori bulunamadı.';
      case 'lookup_query_required':
        return 'Telefon numarası veya kullanıcı adı gir.';
      case 'uploaded_file_not_found':
        return 'Yüklenen dosya bulunamadı.';
      case 'avatar_not_found':
        return 'Avatar bulunamadı.';
      case 'group_title_required':
        return 'Grup adı gerekli.';
      case 'group_min_members_required':
        return 'Bir grup oluşturmak için en az bir kişi daha seçmelisin.';
      case 'group_member_limit_exceeded':
        return 'Bu grup 2048 üye sınırına ulaştı.';
      case 'group_member_not_found':
        return 'Seçilen üyelerden biri bulunamadı.';
      case 'group_member_add_not_allowed':
        return 'Bu gruba üye ekleme yetkin yok.';
      case 'group_invite_not_allowed':
        return 'Bu grupta davet bağlantısı yönetme yetkin yok.';
      case 'group_invite_not_found':
        return 'Davet bağlantısı bulunamadı.';
      case 'group_invite_expired':
        return 'Bu davet bağlantısının süresi dolmuş.';
      case 'group_private':
        return 'Bu grup özel. Katılmak için davet bağlantısı gerekli.';
      case 'group_join_request_review_not_allowed':
        return 'Katılım isteklerini yönetme yetkin yok.';
      case 'group_join_request_not_found':
        return 'Katılım isteği bulunamadı.';
      case 'group_join_banned':
        return 'Bu gruba katılman engellenmiş.';
      case 'group_not_found':
        return 'Grup bulunamadı.';
      case 'group_owner_leave_not_allowed':
        return 'Grup sahibi önce sahipliği devretmeli.';
      case 'group_member_mute_not_allowed':
        return 'Bu üyeyi sessize alma yetkin yok.';
      case 'group_member_ban_not_allowed':
        return 'Bu üyeyi yasaklama yetkin yok.';
      case 'group_pin_not_allowed':
        return 'Bu grupta sabit mesaj yönetme yetkin yok.';
      case 'group_call_state_unavailable':
        return 'Grup çağrısı durumu şu an kullanılamıyor.';
      case 'group_call_type_required':
        return 'Başlatmak için sesli veya görüntülü çağrı seç.';
      case 'group_call_not_allowed':
        return 'Bu grupta çağrı başlatma yetkin yok.';
      case 'group_call_not_active':
        return 'Aktif grup çağrısı bulunamadı.';
      case 'group_call_moderation_not_allowed':
        return 'Bu çağrıyı yönetme yetkin yok.';
      case 'group_ban_not_found':
        return 'Aktif yasak kaydı bulunamadı.';
      case 'chat_send_restricted':
        return 'Bu grupta mesaj gönderme iznin kapalı.';
      case 'chat_rate_limited':
        return 'Çok hızlı mesaj gönderiyorsun. Biraz bekleyip tekrar dene.';
      case 'text_or_attachment_required':
        return 'Mesaj veya ek seçmelisin.';
      case 'call_provider_not_configured':
        return 'Arama servisi henüz hazır değil.';
      case 'call_conflict':
        return 'Kullanıcılardan biri başka bir aramada.';
      case 'invalid_call_target':
        return 'Bu kullanıcı aranamaz.';
      case 'call_not_found':
        return 'Arama kaydı bulunamadı.';
      case 'call_not_ringing':
        return 'Bu arama artik cevaplanamaz.';
      case 'call_not_active':
        return 'Arama zaten sonlanmış.';
      case 'call_not_accepted':
        return 'Bu işlem sadece aktif görüşmede yapılabilir.';
      case 'call_already_video':
        return 'Görüşme zaten görüntülü.';
      case 'video_upgrade_request_conflict':
        return 'Zaten bekleyen bir görüntülü arama isteği var.';
      case 'call_no_pending_video_upgrade':
        return 'Bekleyen görüntülü arama isteği bulunamadı.';
      case 'video_upgrade_invalid_request':
        return 'Bu görüntülü arama isteği geçersiz.';
      case 'account_suspended':
        return 'Hesap geçici olarak durduruldu.';
      case 'account_banned':
        return 'Bu hesap kullanıma kapatıldı.';
      case 'otp_blocked':
        return 'Bu hesap için doğrulama kapatıldı.';
      case 'unauthorized':
      case 'invalid_token':
      case 'session_revoked':
        return 'Oturumun süresi doldu.';
      default:
        return error ?? 'İşlem başarısız ($statusCode)';
    }
  } catch (_) {
    return 'İşlem başarısız ($statusCode)';
  }
}

Never turnaThrowApiError(String body, int statusCode) {
  final message = turnaExtractApiErrorMessage(body, statusCode);
  if (statusCode == 401) {
    throw TurnaUnauthorizedException(message);
  }
  throw TurnaApiException(message);
}
