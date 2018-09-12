
### What's this?

This is a [collectd](https://collectd.org/) plugin to collect CPU temperature by directly reading the sysfs [coretemp/hwmon interface](https://www.kernel.org/doc/Documentation/hwmon/coretemp), without external software (eg, no need to install lm_sensors). 

### Configuration

Place something similar to the following lines in your `collectd.conf`:

```
...
# Load Perl plugin if you weren't loading it already
<LoadPlugin perl>
  Globals true
</LoadPlugin>
...

<Plugin perl>
  IncludeDir "/path/to/collectd_plugins"
  BaseName "Collectd::Plugins"

  ...

  LoadPlugin CPU_temp

  <Plugin CPU_temp>
#    Packages "0" "1"              # optional: which CPU packages (ie, sockets) to monitor, default: all
#    IgnoreSelectedPackages False  # invert package selection, default false. Valid values: False, 0, Off or True, 1, On
#    CoresByLabel "^Phy"           # within each package, select only cores whose lable matches the provided regexp
#    IgnoreSelectedCores False     # ignore matched cores and only monitor the others
#
#    # CoresByLabel, CoresByFile and IgnoreSelectedCores can be overridden on a per-package basis
#    <Package "0">
#      CoresByFile "^Core"
#      IgnoreSelectedCores False
#    </Package>
  </Plugin>

</Plugin>
```

All configuration directives are optional. Here's a bit longer explanation.

Values in the `Packages` directive refer to the corresponding `coretemp.*` directory under `/sys/devices/platform/`, so if you have 2 CPU packages/sockets (`/sys/devices/platform/coretemp.0` and `/sys/devices/platform/coretemp.1`) and say

```
<Plugin CPU_temp>
   Packages "1"
</Plugin>
```

only `/sys/devices/platform/coretemp.1` will be read. You can use `IgnoreSelectedPackages` to exclude, rather than include, the listed packages. By default, all found packages are read.

Cores can be selected in two different, mutually-exclusive ways.

Linux uses sets of files to store individual cores information, and may or may not correspond to the actual CPU core number (_they usually don't, so beware_). For example, you may have a file `/sys/devices/platform/coretemp.0/hwmon/hwmon3/temp2_input` which actually corresponds to **Core 0**, as shown by reading the contents of the associated label file:

```
# cat /sys/devices/platform/coretemp.0/hwmon/hwmon3/temp2_label
Core 0

```

Core labels always seem to have the form `Core X` (corrections welcome).


Also, in some cases there's an extra file set that holds information for the package as a whole (usually it's `temp1_*`, from what I can see):

```
# cat /sys/devices/platform/coretemp.0/hwmon/hwmon3/temp1_label
Package id 0

```

(Note that this label can vary: on some systems it's `Package id X`, on others it's `Physical id X`, and perhaps even different in others - more information welcome).

If you use `CoresByFile`, you have to specify one or more numbers corresponding to those used for the `temp*_` file set you want.
If you use `CoresByLabel`, you have to specify one or more patterns (Perl RE in fact) to select the label content you want.
Finally, you can use `IgnoreSelectedCores` to ignore the selected cores and use only those not selected by your expressions.

These directives can be used both at the global level, in which case they apply to all packages, or can be overridden on a per-package basis.

For example, let's use `CoresByFile` to only monitor the general package temperature for each package (ie, the one in the `temp1_*` files):

```
<Plugin CPU_temp>
  CoresByFile "1"
</Plugin>
```

The same thing can be done by using `CoresByLabel`, as follows:

```
<Plugin CPU_temp>
  CoresByLabel "^(Package|Physical)"
</Plugin>
```

In both cases, if you add a `IgnoreSelectedCores True` you'll get the effect of excluding the general measurement, and including all individual cores. By default, both general amd per-core temperatures are collected.

An example of per-package override (very unlikely that you need this, but just to demonstrate):

```
<Plugin CPU_temp>
  CoresByLabel "^(Package|Physical)"
  <Package "0">
    CoresByLabel "^Core "
  </Package>
</Plugin>
```

So if you have multiple packages, you'll get only the general package temperature for all of them, except for package 0, where you'll get the individual cores and not the general one.

Put the actual plugin (`CPU_temp.pm`) inside `/path/to/collectd_plugins/Collectd/Plugins` (or whatever your `IncludeDir` and `BaseName` above are). Note however that the plugin package name assumes you're using Collectd::Plugins as `BaseName`.
Finally, restart collectd and hopefully see the values being collected.


### Caveats

Only works for Intel CPUs (AFAIK) and only on Linux.
