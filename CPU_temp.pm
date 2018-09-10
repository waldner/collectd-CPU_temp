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
sub get_key {

  my ($key, $ref) = (shift, shift);    # string, array ref

  # array of hash references (usually one element)
  my @results = grep { lc($_->{'key'}) eq lc($key) } @{$ref->{'children'}};

  return @results;
}

# fetch the actual temp values from /sys
sub do_read {

  my %readings;

  for my $package_num (keys %{$CONFIG}) {

    next if ($CONFIG->{$package_num}->{'do'} == 0);

    for my $core_num (keys %{$CONFIG->{$package_num}->{'cores'}}) {

      next if ($CONFIG->{$package_num}->{'cores'}->{$core_num}->{'do'} == 0);

      open(FH, $CONFIG->{$package_num}->{'cores'}->{$core_num}->{'input'}) or next;
      my $temp = <FH>;
      close(FH);
      chomp $temp;
      $readings{$package_num}{$core_num} = $temp / 1000;
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

    # look for available cores
    my @labels = glob("$path/*_label");

    for my $label (@labels) {
      (my $core_num = $label) =~ s|$path/temp(\d+)_label|$1|g;
      open(FH, $label) or next;
      chomp ($CONFIG->{$package_num}->{'cores'}->{$core_num}->{'label'} = <FH>);
      close(FH);
      $CONFIG->{$package_num}->{'cores'}->{$core_num}->{'do'} = 1;
      ($CONFIG->{$package_num}->{'cores'}->{$core_num}->{'input'} = $label) =~ s/_label/_input/;
    }
  }

  # see whether user wants special config
  my $packages_var = (get_key('Packages', $config))[0];

  if ($packages_var) {
    
    # check whether to invert selection
    my $invert = (get_key('IgnoreSelected', $config))[0];

    if ($invert) {
      if ($invert->{'values'}->[0] =~ /^(1|[Tt]rue|[Oo]n)$/) {
        $invert = 1;
      } else {
        $invert = 0;
      } 
    } else {
      $invert = 0;
    }

    if ($invert == 1) {
      # remove wanted packages from those found
      for my $package_num (@{$packages_var->{'values'}}) {
        if (exists $CONFIG->{$package_num}) {
          $CONFIG->{$package_num}->{'do'} = 0;
        }
      }
    } else {

      # remove unwanted packages
      for my $package_num (keys %{$CONFIG}) {
        if ($package_num ~~ @{$packages_var->{'values'}}) {
          $CONFIG->{$package_num}->{'do'} = 1;
        } else {
          $CONFIG->{$package_num}->{'do'} = 0;
        }
      }
    }
  }

  # now check for explicitly included/excluded cores within packages
  my @packages_sections = get_key('Package', $config);

  for my $package_section (@packages_sections) {     # may be empty

    my $package_num = $package_section->{'values'}->[0];

    # avoid useless work
    next if ( (!exists $CONFIG->{$package_num}) || $CONFIG->{$package_num}->{'do'} == 0);

    # get cores and invert for this package
    my $cores_var = (get_key('Cores', $package_section))[0];

    if ($cores_var) {

      # check whether to invert selection
      my $invert = (get_key('IgnoreSelected', $package_section))[0];

      if ($invert) {
        if ($invert->{'values'}->[0] =~ /^(1|[Tt]rue|[Oo]n)$/) {
          $invert = 1;
        } else {
          $invert = 0;
        } 
      } else {
        $invert = 0;
      }

      if ($invert == 1) {
        # remove wanted cores from those found
        for my $core_num (@{$cores_var->{'values'}}) {
          if (exists $CONFIG->{$package_num}->{'cores'}->{$core_num}) {
            $CONFIG->{$package_num}->{'cores'}->{$core_num}->{'do'} = 0;
          }
        }
      } else {
 
        # remove unwanted cores
        for my $core_num (keys %{$CONFIG->{$package_num}->{'cores'}}) {
          if ($core_num ~~ @{$cores_var->{'values'}}) {
            $CONFIG->{$package_num}->{'cores'}->{$core_num}->{'do'} = 1;
          } else {
            $CONFIG->{$package_num}->{'cores'}->{$core_num}->{'do'} = 0;
          }
        }
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
      $v->{type_instance} = $CONFIG->{$package_num}->{'cores'}->{$core_num}->{'label'};
      $v->{values} = [ $readings->{$package_num}->{$core_num} ];
      plugin_dispatch_values($v);
    }
  }

  return 1;

}

plugin_register(TYPE_READ, $plugin_name, "read_func");
plugin_register(TYPE_CONFIG, $plugin_name, "config_func");

1;
