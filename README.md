
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

#        <Plugin CPU_temp>
#          Packages "0" "1"        # optional: which CPU packages to monitor, default: all
#          IgnoreSelected False    # invert package selection, default false. Valid values: False, 0, Off or True, 1, On
#          <Package "0">           # optional per-package config
#            Cores "2" "3"         # within package 0, select cores 2 and 3 (default: all cores)
#            IgnoreSelected False  # invert cores selection, default false
#          </Package>
#        </Plugin>
</Plugin>
```

Values in the `Packages` line refer to the corresponding `coretemp.*` directory under `/sys/devices/platform/`, so if you have 2 CPU packages (`/sys/devices/platform/coretemp.0` and `/sys/devices/platform/coretemp.1`) and say `Packages "1"`, only `/sys/devices/platform/coretemp.1` will be read.

Values in the `Cores` line refer to the file names that Linux uses to store temperature values, and may or may not correspond to the actual CPU core number (`they usually don't, so beware`). For example, you may have a file `/sys/devices/platform/coretemp.0/hwmon/hwmon3/temp2_input` which actually corresponds to *Core 0*, as shown by reading the contents of the associated label file:

```
# cat /sys/devices/platform/coretemp.0/hwmon/hwmon3/temp2_label
Core 0

```

So if you only wanted to read the temperature of core 0, you'd use:

```
   <Package "0">
     Cores "2"
   </Package>
```

Also, in some cases there's an extra file that holds information for the package as a whole (usually it's temp1\_*, from what I can see):

```
# cat /sys/devices/platform/coretemp.0/hwmon/hwmon3/temp1_label
Package id 0

```

So you may want to exclude that one and keep only the individual cores data:

```
   <Package "0">
     Cores "1"
     IgnoreSelected True
   </Package>
```

or only include the global data and exclude the cores:

```
   <Package "0">
     Cores "1"
     IgnoreSelected False   # or just omit this line
   </Package>
```

or read everything, of course, which is the default if no special configuration is specified. 

Put the actual plugin (`CPU_temp.pm`) inside `/path/to/collectd_plugins/Collectd/Plugins` (or whatever your `IncludeDir` and `BaseName` above are).
Finally, restart collectd and hopefully see the values being collected.

