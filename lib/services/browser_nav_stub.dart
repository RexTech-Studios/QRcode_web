/// No-op implementation used on non-web platforms (mobile/admin app builds),
/// where there is no browser history/tab to guard or close.
void pushHistoryGuard() {}

void onPopState(void Function() callback) {}

void onReturnVisible(void Function() callback) {}
