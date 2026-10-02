use v5.36.0;
use utf8;

use Dobby::Boxmate::CIReport;

use JSON::XS ();
use Path::Tiny;
use Test::More;
use Test::Deep ':v1';

my %STEP_FOR = (newt => 'newt_full', cass => 'cassandane');

my sub ok_event ($slug) {
  return { slug => $slug, result => { status_code => 0, exitstatus => 0 } };
}

my sub failed_event ($slug, $exit = 1, $on_fail = 'die') {
  return {
    slug    => $slug,
    on_fail => $on_fail,
    result  => { status_code => $exit << 8, exitstatus => $exit },
  };
}

# Build a report from a description of what the run left behind.
#
#   suites - which suites the plan includes: newt, cass
#   status - what the CI job said: pass or fail
#   events - the content of events.json, or undef for "not there";  if the
#            key is absent entirely, there is no run directory at all
#   files  - other files in the run directory, name => [ lines ]
my sub report_for ($arg) {
  my $plan = {
    program => [ map {; [ $STEP_FOR{$_} ] } $arg->{suites}->@* ],
  };

  my $root    = Path::Tiny->tempdir;
  my $run_dir = $root->child('run-1');

  if (exists $arg->{events}) {
    $run_dir->mkpath;

    $run_dir->child('events.json')->spew_raw(JSON::XS::encode_json($arg->{events}))
      if $arg->{events};

    for my $name (keys $arg->{files}->%*) {
      $run_dir->child($name)->spew_utf8(map {; "$_\n" } $arg->{files}{$name}->@*);
    }
  }

  my $report = Dobby::Boxmate::CIReport->new({
    plan    => $plan,
    run_dir => $run_dir,
    status  => $arg->{status},
    ci_info => $arg->{ci_info} // {},
  });

  # Keep the tempdir alive as long as the report is.
  return ($report, $root);
}

sub report_ok ($desc, $arg, $expect) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my ($report, $root) = report_for($arg);

  subtest $desc => sub {
    is($report->outcome, $expect->{outcome}, "outcome is $expect->{outcome}");

    cmp_deeply(
      { map {; $_->{name} => $_ } $report->suites->@* },
      superhashof($expect->{suites} // {}),
      "suites are as expected",
    );

    cmp_deeply(
      [ map {; $_->{slug} } $report->failed_steps->@* ],
      $expect->{failed_steps} // [],
      "failed steps are as expected",
    );

    cmp_deeply(
      [ $report->trouble ],
      $expect->{trouble} // [],
      "trouble is as expected",
    );

    # Whatever the outcome, every failure should make it into both renderings.
    my @failures = map {; ($_->{failures} // [])->@* } $report->suites->@*;
    my ($text, $html) = ($report->text, $report->html);

    for my $failure (@failures) {
      like($text, qr/\Q$failure\E/, "text mentions $failure");
      like($html, qr/\Q$failure\E/, "html mentions $failure");
    }
  };
}

my %passing_events = (
  newt   => { file_count => 812 },
  events => [ ok_event('fmcyrpkg deploy'), ok_event('yath'), ok_event('cassandane') ],
);

my @cass_ok_log = (
  '[  OK  ] Cyrus::Foo.bar',
  '[  OK  ] Cyrus::Foo.baz',
  '[ SKIP ] Cyrus::Foo.quux',
  '',
  'OK (2 tests, 1 skipped)',
);

report_ok(
  "everything passed",
  {
    suites => [ qw( newt cass ) ],
    status => 'pass',
    events => \%passing_events,
    files  => { newt_failures => [], 'cassandane.log' => \@cass_ok_log },
  },
  {
    outcome => 'success',
    suites  => {
      Fastmail   => superhashof({ state => 'passed', total => 812 }),
      Cassandane => superhashof({ state => 'passed', total => 2 }),
    },
  },
);

report_ok(
  "a suite left out of the plan is not-run, not broken",
  {
    suites => [ qw( newt ) ],
    status => 'pass',
    events => \%passing_events,
    files  => { newt_failures => [] },
  },
  {
    outcome => 'success',
    suites  => {
      Fastmail   => superhashof({ state => 'passed' }),
      Cassandane => superhashof({ state => 'not-run' }),
    },
  },
);

report_ok(
  "failures in both suites are listed",
  {
    suites => [ qw( newt cass ) ],
    status => 'fail',
    events => {
      %passing_events,
      events => [ failed_event('yath', 1, 'mark_failing'), failed_event('cassandane', 1, 'mark_failing') ],
    },
    files  => {
      newt_failures    => [ 't/alpha.t', 't/beta.t' ],
      'cassandane.log' => [ @cass_ok_log, '[FAILED] Cyrus::Foo.boom' ],
      cass_failed      => [ 'Cyrus::Foo.boom' ],
    },
  },
  {
    outcome => 'failure',
    suites  => {
      Fastmail   => superhashof({
        state => 'failed', total => 812, failures => [ 't/alpha.t', 't/beta.t' ],
      }),
      Cassandane => superhashof({
        state => 'failed', total => 3, failures => [ 'Cyrus::Foo.boom' ],
      }),
    },
  },
);

report_ok(
  "a non-suite step failing makes the report a failure",
  {
    suites => [ qw( newt ) ],
    status => 'fail',
    events => {
      %passing_events,
      events => [ ok_event('yath'), failed_event('lg', 2, 'mark_failing') ],
    },
    files  => { newt_failures => [] },
  },
  {
    outcome      => 'failure',
    failed_steps => [ 'lg' ],
  },
);

report_ok(
  "deliberately ignored nonzero exits aren't failures",
  {
    suites => [ qw( newt ) ],
    status => 'pass',
    events => {
      %passing_events,
      events => [ failed_event('knot diff', 1, 'ignore'), ok_event('yath') ],
    },
    files  => { newt_failures => [] },
  },
  { outcome => 'success' },
);

report_ok(
  "no run directory at all",
  { suites => [ qw( newt cass ) ], status => 'fail' },
  {
    outcome => 'trouble',
    trouble => [ "No artifacts were retrieved from the box." ],
    suites  => {
      Fastmail   => { name => 'Fastmail',   unit => 'test files', state => 'broken' },
      Cassandane => { name => 'Cassandane', unit => 'tests',      state => 'broken' },
    },
  },
);

report_ok(
  "a run directory with no events.json",
  { suites => [ qw( newt ) ], status => 'fail', events => undef, files => {} },
  {
    outcome => 'trouble',
    trouble => [ "The box produced no events.json." ],
  },
);

report_ok(
  "a step died",
  {
    suites => [ qw( newt ) ],
    status => 'fail',
    events => {
      fatal_error => { step => 'install_cyrus', error => "it blew up\n" },
      events      => [ failed_event('fmcyrpkg deploy') ],
    },
    files  => {},
  },
  {
    outcome      => 'trouble',
    failed_steps => [ 'fmcyrpkg deploy' ],
    trouble      => [
      "The run died during the install_cyrus step.",
      "Error from install_cyrus: it blew up\n",
    ],
  },
);

report_ok(
  "yath failed, but listed no failed files",
  {
    suites => [ qw( newt ) ],
    status => 'fail',
    events => { %passing_events, events => [ failed_event('yath', 1, 'mark_failing') ] },
    files  => { newt_failures => [] },
  },
  {
    outcome => 'trouble',
    suites  => { Fastmail => superhashof({ state => 'broken', why => re(qr/no test files failed/) }) },
  },
);

report_ok(
  "yath left no failures file",
  {
    suites => [ qw( newt ) ],
    status => 'fail',
    events => \%passing_events,
    files  => {},
  },
  {
    outcome => 'trouble',
    suites  => { Fastmail => superhashof({ state => 'broken', why => re(qr/no summary/) }) },
  },
);

report_ok(
  "cassandane ran nothing",
  {
    suites => [ qw( cass ) ],
    status => 'pass',
    events => \%passing_events,
    files  => { 'cassandane.log' => [ 'Can\'t locate Cassandane/Instance.pm' ] },
  },
  {
    outcome => 'trouble',
    suites  => { Cassandane => superhashof({ state => 'broken', why => re(qr/no tests failed/) }) },
  },
);

report_ok(
  "cassandane failed, but left no cass_failed file",
  {
    suites => [ qw( cass ) ],
    status => 'fail',
    events => { %passing_events, events => [ failed_event('cassandane', 1, 'mark_failing') ] },
    files  => { 'cassandane.log' => \@cass_ok_log },
  },
  {
    outcome => 'trouble',
    suites  => { Cassandane => superhashof({ state => 'broken', why => re(qr/no list of failed tests/) }) },
  },
);

report_ok(
  "cassandane failed, but its cass_failed file was empty",
  {
    suites => [ qw( cass ) ],
    status => 'fail',
    events => { %passing_events, events => [ failed_event('cassandane', 1, 'mark_failing') ] },
    files  => { 'cassandane.log' => \@cass_ok_log, cass_failed => [] },
  },
  {
    outcome => 'trouble',
    suites  => { Cassandane => superhashof({ state => 'broken', why => re(qr/no tests failed/) }) },
  },
);

report_ok(
  "the job failed, but we found nothing wrong",
  {
    suites => [ qw( newt ) ],
    status => 'fail',
    events => \%passing_events,
    files  => { newt_failures => [] },
  },
  {
    outcome => 'trouble',
    trouble => [ "The CI job failed, but no failures were found in its results." ],
  },
);

sub artifacts_link_ok ($desc, $arg, $expect) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my ($report, $root) = report_for({
    suites  => [],
    status  => 'pass',
    ci_info => { job_url => 'https://gitlab.example.com/hm/-/jobs/1' },
    %$arg,
  });

  subtest $desc => sub {
    if (defined $expect) {
      like($report->text, qr/^Artifacts: \Q$expect\E$/m, "text links to artifacts");
      like($report->html, qr/href='\Q$expect\E'/, "html links to artifacts");
    } else {
      unlike($report->text, qr/^Artifacts:/m, "text has no artifacts link");
      unlike($report->html, qr/artifacts\/browse/, "html has no artifacts link");
    }
  };
}

artifacts_link_ok(
  "we link to the run directory in the job's artifacts",
  { events => \%passing_events, files => {} },
  'https://gitlab.example.com/hm/-/jobs/1/artifacts/browse/run-1/',
);

artifacts_link_ok(
  "no artifacts were retrieved, so there's nothing to link to",
  {},
  undef,
);

sub version_links_ok ($desc, $events, $expect) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my ($report, $root) = report_for({
    suites => [],
    status => 'pass',
    events => { %passing_events, %$events },
    files  => {},
  });

  my $html = $report->html;

  subtest $desc => sub {
    for my $url ($expect->{links}->@*) {
      like($html, qr/href='\Q$url\E'/, "links to $url");
    }

    for my $re (($expect->{no_links} // [])->@*) {
      unlike($html, $re, "no link matching $re");
    }
  };
}

version_links_ok(
  "hm and cyrus versions link to gitlab",
  { hm_head => '0123456789abcdef', cyrus_version => 'fmci-20261002.001-gcf1ffd80' },
  {
    links => [
      'https://gitlab.fm/fastmail/hm/-/commit/0123456789abcdef',
      'https://gitlab.fm/fastmail/cyrus-imapd/-/tags/fmci-20261002.001-gcf1ffd80',
    ],
  },
);

version_links_ok(
  "an unknown cyrus version isn't linked",
  { hm_head => '0123456789abcdef', cyrus_version => '' },
  {
    links    => [ 'https://gitlab.fm/fastmail/hm/-/commit/0123456789abcdef' ],
    no_links => [ qr{cyrus-imapd} ],
  },
);

done_testing;
