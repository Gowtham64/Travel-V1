/// Native/no-web fallback: the GSAP web demo isn't available, so callers use
/// the in-app Flutter demo instead.
bool get gsapDemoSupported => false;

/// No-op on non-web platforms.
void openGsapDemo(String jsonData) {}
