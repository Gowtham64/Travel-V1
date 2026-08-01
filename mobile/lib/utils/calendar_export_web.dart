import 'dart:convert';
import 'dart:html' as html;

/// Triggers a browser download of the .ics calendar file. The user's default
/// calendar app (Apple Calendar, Outlook, Google Calendar, …) opens it — we do
/// not force any particular provider.
void downloadIcs(String filename, String content) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/calendar');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
