use v5.36.0;
use utf8;

use Dobby::BoxManager;

use Test::More;
use Test::Deep ':v1';

my %base = (
  username => 'testuser',
  version  => '1.0',
  label    => 'mybox',
);

sub prov_req ($spec) {
  ref $spec eq 'ARRAY'
    ? Dobby::BoxManager::ProvisionRequest->new(@$spec,   digitalocean_ssh_key_name => 'fake-key')
    : Dobby::BoxManager::ProvisionRequest->new({ %$spec, digitalocean_ssh_key_name => 'fake-key'});
}

# Pass a hashref to use hashref construction; pass an arrayref to use
# flat-list construction (the array is spread as the argument list).
sub new_request_ok ($spec, $expect, $description) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my $req = eval { prov_req($spec) };
  cmp_deeply($req, $expect, $description);
}

sub new_request_fail_ok ($spec, $expect, $description) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  eval { prov_req($spec) };
  cmp_deeply($@, $expect, $description);
}

new_request_ok(
  { %base, size => 'big', region => 'nyc' },
  methods(size_preferences => ['big'], region_preferences => ['nyc']),
  'size and region are normalized to single-element preference lists',
);

new_request_ok(
  [%base, size => 'big', region => 'nyc'],
  methods(size_preferences => ['big'], region_preferences => ['nyc']),
  'flat-list construction normalizes the same way as hashref',
);

new_request_ok(
  { %base, size_preferences => [qw(big small)], region_preferences => [qw(nyc sfo)] },
  methods(size_preferences => [qw(big small)], region_preferences => [qw(nyc sfo)]),
  'size_preferences and region_preferences pass through unchanged',
);

new_request_ok(
  { %base, size => 'big' },
  methods(size_preferences => ['big'], region_preferences => []),
  'omitting region leaves region_preferences empty',
);

new_request_fail_ok(
  { %base, size => 'big', size_preferences => ['big'], region => 'nyc' },
  re(qr/exactly one of 'size' or 'size_preferences'/),
  'size and size_preferences together are rejected',
);

new_request_fail_ok(
  { %base, region => 'nyc' },
  re(qr/exactly one of 'size' or 'size_preferences'/),
  'omitting both size and size_preferences is rejected',
);

new_request_fail_ok(
  { %base, size => 'big', region => 'nyc', region_preferences => ['nyc'] },
  re(qr/at most one of 'region' or 'region_preferences'/),
  'region and region_preferences together are rejected',
);

done_testing;
