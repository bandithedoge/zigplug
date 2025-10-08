const std = @import("std");
const c = @import("clap_c");

pub const Feature = enum {
    instrument,
    audio_effect,
    note_effect,
    note_detector,
    analyzer,

    synthesizer,
    sampler,
    drum,
    drum_machine,

    filter,
    phaser,
    equalizer,
    deesser,
    phase_vocoder,
    granular,
    frequency_shifter,
    pitch_shifter,

    distortion,
    transient_shaper,
    compressor,
    expander,
    gate,
    limiter,

    flanger,
    chorus,
    delay,
    reverb,

    tremolo,
    glitch,

    utility,
    pitch_correction,
    restoration,

    multi_effects,

    mixing,
    mastering,

    mono,
    stereo,
    surround,
    ambisonic,

    pub inline fn toString(comptime self: Feature) [:0]const u8 {
        return switch (self) {
            .instrument => c.CLAP_PLUGIN_FEATURE_INSTRUMENT,
            .audio_effect => c.CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
            .note_effect => c.CLAP_PLUGIN_FEATURE_NOTE_EFFECT,
            .note_detector => c.CLAP_PLUGIN_FEATURE_NOTE_DETECTOR,
            .analyzer => c.CLAP_PLUGIN_FEATURE_ANALYZER,
            .synthesizer => c.CLAP_PLUGIN_FEATURE_SYNTHESIZER,
            .sampler => c.CLAP_PLUGIN_FEATURE_SAMPLER,
            .drum => c.CLAP_PLUGIN_FEATURE_DRUM,
            .drum_machine => c.CLAP_PLUGIN_FEATURE_DRUM_MACHINE,
            .filter => c.CLAP_PLUGIN_FEATURE_FILTER,
            .phaser => c.CLAP_PLUGIN_FEATURE_PHASER,
            .equalizer => c.CLAP_PLUGIN_FEATURE_EQUALIZER,
            .deesser => c.CLAP_PLUGIN_FEATURE_DEESSER,
            .phase_vocoder => c.CLAP_PLUGIN_FEATURE_PHASE_VOCODER,
            .granular => c.CLAP_PLUGIN_FEATURE_GRANULAR,
            .frequency_shifter => c.CLAP_PLUGIN_FEATURE_FREQUENCY_SHIFTER,
            .pitch_shifter => c.CLAP_PLUGIN_FEATURE_PITCH_SHIFTER,
            .distortion => c.CLAP_PLUGIN_FEATURE_DISTORTION,
            .transient_shaper => c.CLAP_PLUGIN_FEATURE_TRANSIENT_SHAPER,
            .compressor => c.CLAP_PLUGIN_FEATURE_COMPRESSOR,
            .expander => c.CLAP_PLUGIN_FEATURE_EXPANDER,
            .gate => c.CLAP_PLUGIN_FEATURE_GATE,
            .limiter => c.CLAP_PLUGIN_FEATURE_LIMITER,
            .flanger => c.CLAP_PLUGIN_FEATURE_FLANGER,
            .chorus => c.CLAP_PLUGIN_FEATURE_CHORUS,
            .delay => c.CLAP_PLUGIN_FEATURE_DELAY,
            .reverb => c.CLAP_PLUGIN_FEATURE_REVERB,
            .tremolo => c.CLAP_PLUGIN_FEATURE_TREMOLO,
            .glitch => c.CLAP_PLUGIN_FEATURE_GLITCH,
            .utility => c.CLAP_PLUGIN_FEATURE_UTILITY,
            .pitch_correction => c.CLAP_PLUGIN_FEATURE_PITCH_CORRECTION,
            .restoration => c.CLAP_PLUGIN_FEATURE_RESTORATION,
            .multi_effects => c.CLAP_PLUGIN_FEATURE_MULTI_EFFECTS,
            .mixing => c.CLAP_PLUGIN_FEATURE_MIXING,
            .mastering => c.CLAP_PLUGIN_FEATURE_MASTERING,
            .mono => c.CLAP_PLUGIN_FEATURE_MONO,
            .stereo => c.CLAP_PLUGIN_FEATURE_STEREO,
            .surround => c.CLAP_PLUGIN_FEATURE_SURROUND,
            .ambisonic => c.CLAP_PLUGIN_FEATURE_AMBISONIC,
        };
    }
};
