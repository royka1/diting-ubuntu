// Hardware video decoding on the Xiaomi 12T Pro (iris decoder through the
// libva-v4l2-stateful VA-API driver). Firefox does not enable VA-API on this
// GPU/driver combination by itself.
pref("media.hardware-video-decoding.force-enabled", true);
