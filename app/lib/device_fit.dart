// Client-side "will this run here?" rating for on-device (GGUF) models when
// there's no backend to ask — Android never has one by design, and Windows
// falls back to this too when the backend is unreachable (see
// model_pool.dart's refresh() and _refreshFromBundledRoster()).
//
// Ports the RAM-only shape of Multi-AI/multi_ai/hardware.pyx's
// _rate_on_device_model, with one deliberate change: that function's
// no-VRAM branch can only ever return "possible" or "not_recommended" —
// "optimal" is defined purely as VRAM headroom, which has no equivalent
// here. A literal port would mean no on-device model ever badges green from
// this path, which defeats the point (the README's own note on this gap
// says to rate "against total RAM rather than VRAM", not to drop the green
// tier). So the same three-tier comfort logic used everywhere else in
// hardware.pyx is applied to the RAM budget instead.
import 'api_client.dart';
import 'device_ram.dart';

// Same constants and names as hardware.pyx, kept in lockstep with that file.
const double _ggufOverhead = 1.1; // _GGUF_OVERHEAD
const double _ggufWorkspaceGb = 0.8; // _GGUF_WORKSPACE_GB
const double _ramUsable = 0.7; // _RAM_USABLE
const double _comfort = 0.7; // _COMFORT
const double _cpuFallbackLimitGb = 10.0; // _CPU_FALLBACK_LIMIT_GB

/// Rates [sizeGb] (a GGUF's on-disk/quantized size) against this device's
/// total RAM. Null [sizeGb] mirrors hardware.pyx's rate_model contract — no
/// annotation, since there's nothing to rate.
Future<ModelFit?> rateOnDeviceModel(double? sizeGb) async {
  if (sizeGb == null) return null;
  final need = sizeGb * _ggufOverhead + _ggufWorkspaceGb;
  final ramGb = await totalRamGb();
  if (ramGb == null) {
    return ModelFit(
      rating: ModelFitRating.unknown,
      reason: "Needs about ${_gb(need)}; couldn't read this device's memory.",
      needsGb: need,
    );
  }
  final usable = ramGb * _ramUsable;
  if (need > usable) {
    return ModelFit(
      rating: ModelFitRating.notRecommended,
      reason: 'Needs about ${_gb(need)}, more than the ~${_gb(usable)} usable of this '
          "device's ${_gb(ramGb)} RAM.",
      needsGb: need,
    );
  }
  if (need >= _cpuFallbackLimitGb) {
    return ModelFit(
      rating: ModelFitRating.notRecommended,
      reason: 'About ${_gb(need)} — technically fits in RAM, but far too slow to be '
          'usable on-device (no GPU offload here).',
      needsGb: need,
    );
  }
  if (need <= usable * _comfort) {
    return ModelFit(
      rating: ModelFitRating.optimal,
      reason: "About ${_gb(need)} against this device's ${_gb(ramGb)} RAM — comfortable fit.",
      needsGb: need,
    );
  }
  return ModelFit(
    rating: ModelFitRating.possible,
    reason: "About ${_gb(need)} against this device's ${_gb(ramGb)} RAM — it fits, but with "
        'little headroom. Expect it to be slow.',
    needsGb: need,
  );
}

String _gb(double value) => '${value.toStringAsFixed(1)} GB';
