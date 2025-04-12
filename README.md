# AWA5.zig

Zero dependency interpreter for the AWA5.0 language, written in Zig.

[Language spec](https://github.com/TempTempai/AWA5.0/blob/6fe3b2ef290a3df9c94822634c4ceb6c872cd2fd/AWA5.0%20Specs.pdf)

## Run

```sh
zig build run -- -h
```

## Using in your own project

```sh
zig fetch --save git+https://github.com/TemariVirus/AWA5.zig#GIT_COMMIT_HASH_OR_TAG
```

Then in your `build.zig`:

```zig
const awa5 = b.dependency("AWA5_zig", .{
    .target = target,
    .optimize = optimize,
});
your_module.addImport("awa5", awa5.module("awa5"));
```
