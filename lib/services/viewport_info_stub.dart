/// No-op implementation used on non-web platforms (mobile/admin app
/// builds), where there is no browser window/screen to query and no
/// "Request Desktop Site" mode to detect.
double? physicalScreenWidth() => null;
