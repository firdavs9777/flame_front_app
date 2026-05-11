class RtEvents {
  static const connectionReady = 'connection:ready';
  static const forceDisconnect = 'force_disconnect';
  static const authTokenExpiring = 'auth:token_expiring';
  static const authTokenExpired = 'auth:token_expired';
  static const authTokenRefreshed = 'auth:token_refreshed';
  static const messageNew = 'message:new';
  static const messageSent = 'message:sent';
  static const messageEdited = 'message:edited';
  static const messageDeleted = 'message:deleted';
  static const messageSend = 'message:send';
  static const messageRead = 'message:read';
  static const reactionUpdate = 'reaction:update';
  static const pinUpdate = 'pin:update';
  static const matchNew = 'match:new';
  static const typingStart = 'typing:start';
  static const typingStop = 'typing:stop';
  static const typingUpdate = 'typing:update';
  static const readUpdate = 'read:update';
  static const presenceSubscribe = 'presence:subscribe';
  static const presenceUpdate = 'presence:update';
}

class RtTimeouts {
  static const ackTimeout = Duration(seconds: 8);
  static const typingCoalesce = Duration(seconds: 2);
  static const typingIdle = Duration(seconds: 3);
  static const offlineBannerAfter = Duration(seconds: 30);
}
