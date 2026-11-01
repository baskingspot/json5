const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The one exported module. Everything below is a developer step, so a
    // consumer's fetch graph stops at this module.
    const mod = b.addModule("json5", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (b.pkg_hash.len != 0) return;

    // testingx provides the test runner. It is lazy because only the root
    // build uses it; a consumer never fetches it. On the first configure pass
    // it is not fetched yet, `lazyDependency` returns null, and the build
    // runner fetches it and reruns this script.
    const testingx_dep = b.lazyDependency("testingx", .{ .target = target });
    const test_runner: ?std.Build.Step.Compile.TestRunner = if (testingx_dep) |dep|
        .{ .path = dep.path("src/runner.zig"), .mode = .simple }
    else
        null;

    const test_step = b.step("test", "Run the unit tests and the json5-tests corpus");

    const mod_tests = b.addTest(.{ .root_module = mod, .test_runner = test_runner });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    // The corpus tests read `test/json5-tests` at run time, so the runner's
    // working directory is the build root.
    const corpus_mod = b.createModule(.{
        .root_source_file = b.path("test/corpus.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "json5", .module = mod }},
    });
    const corpus_tests = b.addTest(.{ .root_module = corpus_mod, .test_runner = test_runner });
    const run_corpus_tests = b.addRunArtifact(corpus_tests);
    run_corpus_tests.setCwd(b.path("."));
    test_step.dependOn(&run_corpus_tests.step);

    // The guide's examples are real programs against the public module,
    // tested with everything else so a guide page cannot show code that does
    // not build.
    const examples_mod = b.createModule(.{
        .root_source_file = b.path("docs/examples/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "json5", .module = mod }},
    });
    const example_tests = b.addTest(.{ .root_module = examples_mod, .test_runner = test_runner });
    const run_example_tests = b.addRunArtifact(example_tests);
    test_step.dependOn(&run_example_tests.step);
}
