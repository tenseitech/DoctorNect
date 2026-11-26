import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/config/app_web_urls.dart';

void main() {
  test('default public web URLs use doctornect.com', () {
    expect(AppWebUrls.websiteUrl, 'https://doctornect.com');
    expect(AppWebUrls.inviteJoinUrl, 'https://doctornect.com/join');
    expect(AppWebUrls.ambulanceSetupUrl, 'https://doctornect.com/ambulance-setup');
    expect(AppWebUrls.appDownloadUrl, 'https://doctornect.com/download');
    expect(AppWebUrls.supportEmail, 'support@doctornect.com');
  });
}