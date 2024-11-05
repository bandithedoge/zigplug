const std = @import("std");
const zigplug = @import("zigplug");
const clap = @import("c");

const FeatureMap = std.EnumArray(zigplug.Feature, [*c]const u8);

// TODO: parse features properly
pub fn parseFeatures(comptime features: []const zigplug.Feature) [*c]const [*c]const u8 {
    const map = FeatureMap.init(.{
        .instrument = clap.CLAP_PLUGIN_FEATURE_INSTRUMENT,
        .effect = clap.CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
        .note_effect = clap.CLAP_PLUGIN_FEATURE_NOTE_EFFECT,
        .note_detector = clap.CLAP_PLUGIN_FEATURE_NOTE_DETECTOR,
        .analyzer = clap.CLAP_PLUGIN_FEATURE_ANALYZER,
        .synthesizer = clap.CLAP_PLUGIN_FEATURE_SYNTHESIZER,
        .sampler = clap.CLAP_PLUGIN_FEATURE_SAMPLER,
        .drum = clap.CLAP_PLUGIN_FEATURE_DRUM,
        .drum_machine = clap.CLAP_PLUGIN_FEATURE_DRUM_MACHINE,
        .filter = clap.CLAP_PLUGIN_FEATURE_FILTER,
        .phaser = clap.CLAP_PLUGIN_FEATURE_PHASER,
        .equalizer = clap.CLAP_PLUGIN_FEATURE_EQUALIZER,
        .deesser = clap.CLAP_PLUGIN_FEATURE_DEESSER,
        .phase_vocoder = clap.CLAP_PLUGIN_FEATURE_PHASE_VOCODER,
        .granular = clap.CLAP_PLUGIN_FEATURE_GRANULAR,
        .frequency_shifter = clap.CLAP_PLUGIN_FEATURE_FREQUENCY_SHIFTER,
        .pitch_shifter = clap.CLAP_PLUGIN_FEATURE_PITCH_SHIFTER,
        .distortion = clap.CLAP_PLUGIN_FEATURE_DISTORTION,
        .transient_shaper = clap.CLAP_PLUGIN_FEATURE_TRANSIENT_SHAPER,
        .compressor = clap.CLAP_PLUGIN_FEATURE_COMPRESSOR,
        .expander = clap.CLAP_PLUGIN_FEATURE_EXPANDER,
        .gate = clap.CLAP_PLUGIN_FEATURE_GATE,
        .limiter = clap.CLAP_PLUGIN_FEATURE_LIMITER,
        .flanger = clap.CLAP_PLUGIN_FEATURE_FLANGER,
        .chorus = clap.CLAP_PLUGIN_FEATURE_CHORUS,
        .delay = clap.CLAP_PLUGIN_FEATURE_DELAY,
        .reverb = clap.CLAP_PLUGIN_FEATURE_REVERB,
        .tremolo = clap.CLAP_PLUGIN_FEATURE_TREMOLO,
        .glitch = clap.CLAP_PLUGIN_FEATURE_GLITCH,
        .utility = clap.CLAP_PLUGIN_FEATURE_UTILITY,
        .pitch_correction = clap.CLAP_PLUGIN_FEATURE_PITCH_CORRECTION,
        .restoration = clap.CLAP_PLUGIN_FEATURE_RESTORATION,
        .multi_effects = clap.CLAP_PLUGIN_FEATURE_MULTI_EFFECTS,
        .mixing = clap.CLAP_PLUGIN_FEATURE_MIXING,
        .mastering = clap.CLAP_PLUGIN_FEATURE_MASTERING,
        .mono = clap.CLAP_PLUGIN_FEATURE_MONO,
        .stereo = clap.CLAP_PLUGIN_FEATURE_STEREO,
        .surround = clap.CLAP_PLUGIN_FEATURE_SURROUND,
        .ambisonic = clap.CLAP_PLUGIN_FEATURE_AMBISONIC,
    });
    _ = map; // autofix

    const result: [features.len:null]?[*:0]const u8 = undefined;

    return result;
}
