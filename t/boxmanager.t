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

sub mk_taskstream_ok ($extra, $description) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my $boxman = Dobby::BoxManager->new(dobby => make_dobby(), %base, %$extra);
  is(ref $boxman->_mk_taskstream, 'CODE', $description);
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
  { taskstream_factory => sub { }, logsnippet_cb => sub { } },
  re(qr/one of taskstream_factory or logsnippet_cb but both were provided/),
  'BoxManager rejects both stream callbacks at once',
);

mk_taskstream_ok(
  {},
  'BoxManager with neither stream cb synthesizes a taskstream callback',
);

subtest 'taskstream_factory is called fresh for each phase' => sub {
  my $calls = 0;
  my $boxman = Dobby::BoxManager->new(
    dobby => make_dobby(),
    %base,
    taskstream_factory => sub { my $n = ++$calls; return sub { $n } },
  );

  my $first  = $boxman->_mk_taskstream;
  my $second = $boxman->_mk_taskstream;

  is($calls, 2, 'factory was invoked once per _mk_taskstream call');
  isnt($first, $second, 'each phase gets a distinct callback');
};

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
