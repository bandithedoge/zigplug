const GainExample = @import("GainExample");

comptime {
    @import("zigplug_clap").exportClap(GainExample, .{
        .id = "com.bandithedoge.zigplug_gain_example",
        .features = &.{ .audio_effect, .mono, .stereo, .utility },
    });
}
