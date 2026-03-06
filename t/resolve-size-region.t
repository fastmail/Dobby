use v5.36.0;
use utf8;

use lib 't/lib';

use Dobby::BoxManager;
use Dobby::TestClient;

use Test::More;
use Test::Deep ':v1';

# The size slugs are nonsense, but naming them this way makes the tests easier
# to read.
my $sizes_page = {
  sizes => [
    { slug => 'everywhere', available => 1, regions => [qw(nyc sfo ams)] },
    { slug => 'not-ams',    available => 1, regions => [qw(nyc sfo)]     },
    { slug => 'only-sfo',   available => 1, regions => [qw(sfo)]         },
    { slug => 'nowhere',    available => 0, regions => [qw(nyc sfo ams)] },
  ],
};

my sub _get_size_and_region ($spec, $snapshot) {
  my $dobby = Dobby::TestClient->new(bearer_token => 'test-token');
  $dobby->register_url_json('/sizes', $sizes_page);

  my $boxman = Dobby::BoxManager->new(
    dobby         => $dobby,
    box_domain    => 'fm.example.com',
    error_cb      => sub ($err, @) { die $err },
    message_cb    => sub { },
    log_cb        => sub { },
    logsnippet_cb => sub { },
  );

  my $prov_req = Dobby::BoxManager::ProvisionRequest->new(
    username => 'testuser',
    version  => '1.0',
    label    => 'test',
    %$spec,
  );

  my %got;
  @got{qw( size region )} = $boxman->_resolve_size_and_region($prov_req, $snapshot)->get;

  return \%got;
}

sub box_choices_ok ($spec, $snapshot, $expect, $description) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $got = _get_size_and_region($spec, $snapshot);

  cmp_deeply(
    $got,
    $expect,
    "$description: picked the expected size/region",
  );
}

sub box_choices_fail_ok ($spec, $snapshot, $expect, $description) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  eval { _get_size_and_region($spec, $snapshot) };

  my $error = $@;

  cmp_deeply(
    $error,
    $expect,
    "$description: jailed the expected way",
  );
}

# This mocks up just as much of a Digital Ocean API snapshot object as is
# needed for the region picker to do its thing.
sub found_in (@regions) {
  return { name => 'fminabox-1.0', regions => [ @regions ] };
}

box_choices_ok(
  { size => 'everywhere', region => 'nyc' },
  found_in(qw( nyc sfo )),
  { size => 'everywhere', region => 'nyc' },
  'single option, and you can have it',
);

box_choices_fail_ok(
  { size => 'everywhere', region => 'nyc' },
  found_in(qw(sfo)),
  all( re(qr/isn't available in NYC/), re(qr/SFO/) ),
  "single option, not available",
);

box_choices_ok(
  { size => 'everywhere', region => 'nyc' },
  undef,
  { size => 'everywhere', region => 'nyc' },
  'no snapshot means no region check',
);

box_choices_ok(
  {
    size_preferences => [qw(not-ams everywhere)],
    region           => 'nyc',
  },
  found_in(qw(nyc sfo)),
  { size => 'not-ams', region => 'nyc' },
  'multiple sizes: first size available in region is chosen',
);

box_choices_ok(
  {
    size_preferences => [qw(only-sfo everywhere)],
    region           => 'nyc',
  },
  found_in(qw(nyc sfo)),
  { size => 'everywhere', region => 'nyc' },
  'only-sfo is only in sfo, so it falls back to everywhere'
);


# prefer_proximity=0 (default): size wins.
# only-sfo is not in nyc but IS in sfo → (only-sfo, sfo)
# beats everywhere in nyc.
box_choices_ok(
  {
    size_preferences   => [qw(only-sfo everywhere)],
    region_preferences => [qw(nyc sfo)],
  },
  found_in(qw(nyc sfo)),
  { size => 'only-sfo', region => 'sfo' },
  'prefer_proximity=0: we pick size over region',
);

# prefer_proximity=1: region wins.
# Best result in nyc is everywhere (only-sfo not there) → (everywhere, nyc)
# beats (only-sfo, sfo).
box_choices_ok(
  {
    size_preferences   => [qw(only-sfo everywhere)],
    region_preferences => [qw(nyc sfo)],
    prefer_proximity   => 1,
  },
  found_in(qw(nyc sfo)),
  { size => 'everywhere', region => 'nyc' },
  'prefer_proximity=1: we pick regionover size',
);

# Snapshot has only sfo, so that is the only candidate region.
box_choices_ok(
  { size => 'everywhere' },
  found_in(qw(sfo)),
  { size => 'everywhere', region => 'sfo' },
  'no region preference: picks from snapshot regions',
);

box_choices_ok(
  {
    size_preferences   => [qw(everywhere)],
    region_preferences => [qw(nyc sfo)],
  },
  found_in(qw(sfo)),
  { size => 'everywhere', region => 'sfo' },
  "skip first-choice region because of snapshot availability",
);

box_choices_ok(
  { size => 'only-sfo' },
  undef,
  { size => 'only-sfo', region => 'sfo' },
  'no region, but size only in one region',
);

box_choices_fail_ok(
  {
    size_preferences   => [qw(only-sfo not-ams)],
    region_preferences => [qw(ams)],
  },
  found_in(qw(nyc sfo)),
  re(qr/No available combination/),
  'nothing satisfies criteria'
);

# only-sfo is not in ams, but fallback_to_anywhere lets it land in sfo.
box_choices_ok(
  {
    size_preferences     => [qw(only-sfo)],
    region_preferences   => [qw(ams)],
    fallback_to_anywhere => 1,
  },
  found_in(qw(ams sfo)),
  { size => 'only-sfo', region => 'sfo' },
  'fallback_to_anywhere: preferred region misses, falls through to any region',
);

done_testing;
