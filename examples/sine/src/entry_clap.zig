const SineExample = @import("SineExample");

comptime {
    @import("zigplug_clap").exportClap(SineExample, .{
        .id = "com.bandithedoge.zigplug_gain_example",
        .features = &.{ .audio_effect, .mono, .stereo, .utility },
    });
}
