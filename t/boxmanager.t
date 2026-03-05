use v5.36.0;
use utf8;

use lib 't/lib';

use Dobby::BoxManager;
use Dobby::TestClient;

use Test::More;
use Test::Deep ':v1';

my %base = (
  box_domain => 'fm.example.com',
  error_cb   => sub ($err, @) { die $err },
  message_cb => sub { },
  log_cb     => sub { },
);

my @TEST_SNAPSHOTS = (
  {
    id         => 1,
    name       => 'fminabox-1.0-20260101',
    created_at => '2026-01-01T00:00:00Z',
    regions    => [qw(nyc sfo)]
  },
  {
    id         => 2,
    name       => 'fminabox-1.0-20260201',
    created_at => '2026-02-01T00:00:00Z',
    regions    => [qw(nyc sfo)]
  },
  {
    id         => 3,
    name       => 'fminabox-2.0-20260101',
    created_at => '2026-01-01T00:00:00Z',
    regions    => [qw(nyc)]
  },
);

sub make_dobby () {
  Dobby::TestClient->new(bearer_token => 'test-token');
}

sub new_boxman_fail_ok ($extra, $expect, $description) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  eval { Dobby::BoxManager->new(dobby => make_dobby(), %base, %$extra) };
  cmp_deeply($@, $expect, $description);
}

sub snapshot_for_version_ok ($version, $expect, $description) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my $dobby = make_dobby();
  $dobby->register_url_json('/snapshots', { snapshots => \@TEST_SNAPSHOTS });
  my $boxman = Dobby::BoxManager->new(dobby => $dobby, %base, logsnippet_cb => sub { });
  my $got = $boxman->get_snapshot_for_version($version)->get;
  cmp_deeply($got, $expect, $description);
}

sub snapshot_for_version_fail_ok ($version, $expect, $description) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my $dobby = make_dobby();
  $dobby->register_url_json('/snapshots', { snapshots => \@TEST_SNAPSHOTS });
  my $boxman = Dobby::BoxManager->new(dobby => $dobby, %base, logsnippet_cb => sub { });
  eval { $boxman->get_snapshot_for_version($version)->get };
  cmp_deeply($@, $expect, $description);
}

new_boxman_fail_ok(
  {},
  re(qr/requires one of taskstream_cb or logsnippet_cb but neither/),
  'BoxManager requires at least one stream callback',
);

new_boxman_fail_ok(
  { taskstream_cb => sub { }, logsnippet_cb => sub { } },
  re(qr/requires one of taskstream_cb or logsnippet_cb but both/),
  'BoxManager rejects both stream callbacks at once',
);

snapshot_for_version_ok(
  '1.0',
  {
    id         => 2,
    name       => 'fminabox-1.0-20260201',
    created_at => '2026-02-01T00:00:00Z',
    regions    => [qw(nyc sfo)]
  },
  'returns the most recent snapshot for the requested version',
);

snapshot_for_version_ok(
  '2.0',
  {
    id         => 3,
    name       => 'fminabox-2.0-20260101',
    created_at => '2026-01-01T00:00:00Z',
    regions    => [qw(nyc)]
  },
  'version filter excludes snapshots for other versions',
);

snapshot_for_version_fail_ok(
  '3.0',
  re(qr/no snapshot found for fminabox-3\.0/),
  'error when no snapshot matches the requested version',
);

done_testing;
