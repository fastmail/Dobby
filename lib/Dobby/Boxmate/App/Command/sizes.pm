package Dobby::Boxmate::App::Command::sizes;
use Dobby::Boxmate::App -command;

# ABSTRACT: show available droplet sizes for an image

use v5.36.0;
use utf8;

sub abstract { 'show available droplet sizes for an image' }

sub usage_desc { '%c sizes %o' }

sub opt_spec {
  return (
    [ 'version|v=s',            'image version to use' ],
    [ 'snapshot-id|snapshot=i', 'DigitalOcean snapshot to use (numeric id)' ],
    [ 'price=f',                'target hourly price; show sizes within 50%-200% of this value' ],
    [ 'min-disk=i',             'minimum disk size in GB' ],
    [ 'min-cpu=i',              'minimum number of vCPUs' ],
    [ 'min-ram=i',              'minimum RAM in GB' ],
    [],
    [ 'type' => 'hidden' => {
        default => 'inabox',
        one_of  => [
          [ 'inabox',   "fminabox snapshot (default)" ],
          [ 'debian',   "stock Debian image" ],
          [ 'docker',   "stock Docker image" ],
        ]
      }
    ],
  );
}

sub validate_args ($self, $opt, $args) {
  if (defined $opt->snapshot_id) {
    $opt->snapshot_id =~ /\A[0-9]+\z/
      || die "The snapshot id must be numeric\n";

    die "You can't use --snapshot-id and --version together\n" if defined $opt->version;
  }
}

sub execute ($self, $opt, $args) {
  my $config = $self->app->config;
  my $boxman = $self->boxman;
  my $dobby  = $boxman->dobby;

  my ($snapshot, $image_name);

  if (defined $opt->snapshot_id) {
    my $res = $dobby->json_get("/snapshots/" . $opt->snapshot_id, { undef_if_404 => 1 })->get;
    $snapshot   = $res && $res->{snapshot};
    die "No snapshot found for id " . $opt->snapshot_id . "\n" unless $snapshot;
    $image_name = $snapshot->{name};
  } elsif ($opt->debian) {
    $image_name = 'debian-12-x64 (stock, all regions)';
  } elsif ($opt->docker) {
    $image_name = 'docker-20-04 (stock, all regions)';
  } else {
    my $version = $opt->version // $config->version;
    $snapshot   = $boxman->get_snapshot_for_version($version)->get;
    $image_name = $snapshot->{name};
  }

  my $candidate_set = $boxman->find_provisioning_candidates(
    snapshot  => $snapshot,
    (defined $opt->price    ? (max_price => $opt->price * 2.0,
                               min_price => $opt->price * 0.5) : ()),
    (defined $opt->min_disk ? (min_disk  => $opt->min_disk)    : ()),
    (defined $opt->min_cpu  ? (min_cpu   => $opt->min_cpu)     : ()),
    (defined $opt->min_ram  ? (min_ram   => $opt->min_ram)     : ()),
  )->get;

  my @all_candidates = $candidate_set->candidates;

  # One display row per unique size slug; use the first candidate seen for
  # the size's metadata (all candidates for a slug share the same metadata).
  my %size_meta;
  for my $c (@all_candidates) {
    $size_meta{$c->{size}} //= $c;
  }

  my @sizes = sort { ($a->{description} // '') cmp ($b->{description} // '')
                  ||  $a->{price_hourly} <=>  $b->{price_hourly} }
              values %size_meta;

  my %seen_region;
  my @sorted_regions = sort grep { !$seen_region{$_}++ }
                       map  { $_->{region} }
                       @all_candidates;

  my %valid;
  for my $c (@all_candidates) {
    $valid{$c->{size}}{$c->{region}} = 1;
  }

  require Text::Table;
  require Term::ANSIColor;

  my @region_columns = map { { title => $_, align_title => 'center' } } @sorted_regions;

  my $table = Text::Table->new(
    'slug',
    'category',
    { title => 'mem',  align => 'right', align_title => 'right' },
    { title => 'vcpu', align => 'right', align_title => 'right' },
    { title => 'disk', align => 'right', align_title => 'right' },
    { title => '$/hr', align => 'right', align_title => 'right' },
    @region_columns,
  );

  for my $size (@sizes) {
    my $mem = $size->{memory} >= 1024
            ? ($size->{memory} / 1024) . 'G'
            : $size->{memory} . 'M';

    my @region_cells = map { $valid{$size->{size}}{$_} ? "\N{CHECK MARK}" : q{ } } @sorted_regions;

    $table->add(
      $size->{size},
      $size->{description} // '',
      $mem,
      $size->{vcpus},
      $size->{disk} . 'G',
      sprintf('$%.3f', $size->{price_hourly}),
      @region_cells,
    );
  }

  say "Image: $image_name";
  say "";
  print Term::ANSIColor::colored(['bold', 'bright_white'], qq{ $_}) for $table->title;
  print for $table->body;

  return;
}

1;
