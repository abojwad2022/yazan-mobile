/// Counts the bytes this app moved, so the Data Saver screen can show real numbers.
///
/// Request/response body lengths only (headers are not counted), so it slightly
/// under-reports; the screen says so.
class TrafficMeter {
  int sentBytes = 0;
  int receivedBytes = 0;
  int notModified = 0;

  int get totalBytes => sentBytes + receivedBytes;

  void reset() {
    sentBytes = 0;
    receivedBytes = 0;
    notModified = 0;
  }
}
