/// Height of the blurred zone under the top bar, in logical px.
const double kZoneHeight = 120;

/// Height of the blurred zone above the bottom bars (S2, S3), in logical px.
const double kFooterZoneHeight = 168;

/// The sigma the app under test uses, in LOGICAL px: 44 device px at 3x.
///
/// inspire_blur takes sigma in DEVICE px (see `deviceSigma`), whereas
/// `ImageFilter.blur` takes logical px.
const double kBlurLogicalSigma = 44 / 3;

/// Scroll distance over which a scroll-driven blur ramps from 0 to full sigma.
const double kScrollRampDistance = 80;

/// Height of the top bar overlay: a 56 px app bar plus a 48 px row.
const double kHeaderHeight = 104;

/// Height of the mini player plus the navigation bar, in logical px.
const double kBottomBarsHeight = 64 + 80;
