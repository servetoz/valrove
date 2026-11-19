/// Whether this is the Google Play build (`--dart-define=STORE=play`). It
/// leaves out the Donate page under About and the links for supporting
/// Valetudo; the donation popup stays.
const playStoreBuild = String.fromEnvironment('STORE') == 'play';
