# neocities-zig
neocities-zig is a CLI and a library for the [Neocities](https://neocities.org)
REST [API](https://https://neocities.org/api).

## CLI Installation

### AUR (Arch Linux)

```
git clone https://aur.archlinux.org/neocities-zig-bin.git
cd neocities-zig-bin
makepkg -si
```

### Manual Installation (Linux)

Grab one of the [release](https://github.com/Ratakor/neocities-zig/releases)
according to your system.

### Building (Mac OSX, Windows, ...)

Requires zig 0.13.0.
```
git clone https://github.com/ratakor/neocities-zig.git
cd neocities-zig
zig build -Doptimize=ReleaseSafe
```

## Configuration

### Config File
When launching `neocities` for the first time you will be granted with a menu
where you can enter your username and password. This will get an api key from
neocities and save it in a config file so you won't have to connect again.

### Environment Variables
- NEOCITIES_API_KEY: use this if you don't want a config file.
- NEOCITIES_USERNAME: only used for setting up the config file.
- NEOCITIES_PASSWORD: only used for setting up the config file.

## Library Installation

Add it to an existing project with this command:
```
zig fetch --save https://github.com/ratakor/neocities-zig/archive/master.tar.gz
```

Add the module to build.zig like that:
```zig
const neocities = b.dependency("neocities", .{});
exe.root_module.addImport("Neocities", neocities.module("neocities"));
```

And import it on a file.zig:
```zig
const Neocities = @import("Neocities");
```

Check [src/main.zig](src/main.zig) for a detailed example on how to use the library.

## CLI Usage
```
Usage: neocities <command> [options]

Commands:
  upload     | Upload files to your Neocities website.
  delete     | Delete files from your Neocities website.
  info       | Display information about a Neocities website.
  list       | List files from your Neocities website.
  key        | Display the API key.
  logout     | Remove the API key from the configuration file.
  help       | Display information about a command.
  version    | Display program version.
```
