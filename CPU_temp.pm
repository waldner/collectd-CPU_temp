=head1 NAME

cpu_temp - collectd plugin to gather CPU temperature.

=head1 DESCRIPTION

This plugin reads CPU temperature using the hwmon/coretemp interface in /sys directly.
No additional software installation (eg, lm-sensors) necessary.

=cut

package Collectd::Plugins::CPU_temp;

use strict;
use warnings;

use Collectd qw( :all );

use Data::Dumper;

my $plugin_name = "CPU_temp";
my $CONFIG;

my $SYS_PATH = '/sys/devices/platform';


#### Utility function(s) ####################################################

# search for hash with key "$key" among the children of the given ref
# optionally takes a value, in which case only the key(s) with that value
# is selected
sub get_key {

  my ($key, $ref, $value) = (shift, shift, shift);    # string, array ref, string (optional)

  # array of hash references (usually one element)
  my @results = grep { lc($_->{'key'}) eq lc($key) } @{$ref->{'children'}};

  if (defined($value)) {
    @results = grep { $_->{'values'}->[0] eq $value } @results;
  }

  return @results;
}


# fetch the actual temp values from /sys
sub do_read {

  my %readings;

  for my $package_num (keys %{$CONFIG}) {

    next if ($CONFIG->{$package_num}->{'do'} == 0);

    for my $core_elem (@{$CONFIG->{$package_num}->{'cores'}}) {
      next if ($core_elem->{'do'} == 0);
      open(FH, $core_elem->{'input'}) or next;
      my $temp = <FH>;
      close(FH);
      chomp $temp;
      $readings{$package_num}->{$core_elem->{'label'}} = $temp / 1000;
    }
  }
  return \%readings;
}


#### Collectd callbacks #####################################################

# callback to initialize plugin
sub config_func {

  my $config = shift;

  plugin_log(LOG_INFO, "$plugin_name: config function invoked");

  # discover what's available
  my @paths = glob("$SYS_PATH/coretemp.*/hwmon/hwmon*");

  if (!@paths) {
    plugin_log(LOG_ERR, "$plugin_name: Nothing found under $SYS_PATH, terminating");
    exit 1
  }

  # populate config
  for my $path (@paths) {
    (my $package_num = $path) =~ s|$SYS_PATH/coretemp\.(\d+).*|$1|g;
    $CONFIG->{$package_num}->{'path'} = $path;
    $CONFIG->{$package_num}->{'do'} = 1;

    $CONFIG->{$package_num}->{'cores'} = [];

    # look for available cores
    my @labels = glob("$path/*_label");

    for my $label (@labels) {
      my %core;
      (my $core_num = $label) =~ s|$path/temp(\d+)_label|$1|g;
      $core{'byfile'} = $core_num;
      open(FH, $label) or next;
      chomp ($core{'label'} = <FH>);
      close(FH);
      $core{'do'} = 1;
      ($core{'input'} = $label) =~ s/_label/_input/;

      push @{$CONFIG->{$package_num}->{'cores'}}, \%core;
    }
  }

  # see whether user wants special config
  my $packages_var = (get_key('Packages', $config))[0];

  if ($packages_var) {
    
   for my $package_num (keys %{$CONFIG}) {
      if (!($package_num ~~ @{$packages_var->{'values'}})) {
        $CONFIG->{$package_num}->{'do'} = 0;
      }
    }

    # check whether to invert selection
    my $packages_invert = (get_key('IgnoreSelected', $config))[0];

    if ($packages_invert) {
      if ($packages_invert->{'values'}->[0] =~ /^(1|[Tt]rue|[Oo]n)$/) {
        $packages_invert = 1;
      } else {
        $packages_invert = 0;
      } 
    } else {
      $packages_invert = 0;
    }

    if ($packages_invert == 1) {
      for my $package_num (keys %{$CONFIG}) {
        $CONFIG->{$package_num}->{'do'} = 1 - $CONFIG->{$package_num}->{'do'};
      }
    }
  }

  # get global core selection, if any
  my $coresbyfile_var = (get_key('CoresByFile', $config))[0];
  my $coresbylabel_var = (get_key('CoresByLabel', $config))[0];

  if ($coresbyfile_var && $coresbylabel_var) {
    plugin_log(LOG_ERR, "$plugin_name: CoresByFile and CoresByLabel are mutually exclusive (global section)");
    exit 1;
  }

  my $cores_invert = (get_key('IgnoreSelectedCores', $config))[0];

  for my $package_num (keys %{$CONFIG}) {

    # avoid useless work
    next if ($CONFIG->{$package_num}->{'do'} == 0);

    # check whether there's an overridden cores config for this package
    my $package_section = (get_key('Package', $config, $package_num))[0];

    if ($package_section) {
      plugin_log(LOG_INFO, "$plugin_name: Found overridden package section for package $package_num");
      my $overridden_coresbyfile_var = (get_key('CoresByFile', $package_section))[0];
      my $overridden_coresbylabel_var = (get_key('CoresByLabel', $package_section))[0];
      my $overridden_cores_invert = (get_key('IgnoreSelectedCores', $package_section))[0];

      if ($overridden_coresbyfile_var && $overridden_coresbylabel_var) {
        plugin_log(LOG_ERR, "$plugin_name: CoresByFile and CoresByLabel are mutually exclusive (Package $package_num section)");
        exit 1;
      }

      if ($overridden_coresbyfile_var) {
        $coresbyfile_var = $overridden_coresbyfile_var;
      }
      if ($overridden_coresbylabel_var) {
        $coresbylabel_var = $overridden_coresbylabel_var;
      }

      if ($overridden_coresbyfile_var || $overridden_coresbylabel_var) {
        if ($overridden_cores_invert) {
          $cores_invert = $overridden_cores_invert;
        }
      }
    }

    my $invert = 0;

    if ($coresbyfile_var || $coresbylabel_var) {
      if ($cores_invert) {
        if ($cores_invert->{'values'}->[0] =~ /^(1|[Tt]rue|[Oo]n)$/) {
          $invert = 1;
        } else {
          $invert = 0;
        }
      } else {
        $invert = 0;
      }
    }

    if ($coresbyfile_var) {
      # remove unwanted cores
      for my $core_elem (@{$CONFIG->{$package_num}->{'cores'}}) {
        if ($core_elem->{'byfile'} ~~ @{$coresbyfile_var->{'values'}}) {
          $core_elem->{'do'} = 1;
        } else {
          $core_elem->{'do'} = 0;
        }
      }
    } elsif ($coresbylabel_var) {

      for my $core_elem (@{$CONFIG->{$package_num}->{'cores'}}) {
        my $selected = 0;
        for my $core_pat (@{$coresbylabel_var->{'values'}}) {
          if ($core_elem->{'label'} =~ m|$core_pat|i) {
            $selected = 1;
          }
        }
        if ($selected == 0) {
          $core_elem->{'do'} = 0;
        }
      }
    }

    if ($invert == 1) {
      for my $core_elem (@{$CONFIG->{$package_num}->{'cores'}}) {
        $core_elem->{'do'} = 1 - $core_elem->{'do'};
      }
    }
  }

  #$Data::Dumper::Indent = 0;
  #plugin_log(LOG_INFO, Dumper($CONFIG));
  return 1;

}


# callback to collect the data and dispatch it
sub read_func {

  my $readings = do_read();

  my $v = {
    plugin   => $plugin_name,
    type     => "gauge",
    interval => plugin_get_interval()
  };

  for my $package_num (keys %{$readings}) {

    for my $core_num (keys %{$readings->{$package_num}}) {

      $v->{plugin_instance} = $package_num;
      $v->{type_instance} = $core_num;
      $v->{values} = [ $readings->{$package_num}->{$core_num} ];
      plugin_dispatch_values($v);
    }
  }

  return 1;

}

plugin_register(TYPE_READ, $plugin_name, "read_func");
plugin_register(TYPE_CONFIG, $plugin_name, "config_func");

1;
