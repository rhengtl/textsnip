/// IsolateNameServer port names used for communication between the main
/// isolate and the flutter_overlay_window isolate.
///
/// The package's own shareData/overlayListener (a BasicMessageChannel) does not
/// reliably deliver overlay→main messages, so — like the package's official
/// example — we use SendPort/ReceivePort registered with IsolateNameServer,
/// which is process-global and works across both isolates.
const String kMainIsolatePort = 'textsnip_main';
const String kOverlayIsolatePort = 'textsnip_overlay';
