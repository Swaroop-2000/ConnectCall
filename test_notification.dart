
import 'dart:html' as html;
void main() {
  html.Notification.requestPermission().then((permission) {
    if (permission == 'granted') {
      html.Notification('Test Notification', body: 'This is a test');
    }
  });
}
