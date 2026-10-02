package Dobby::Boxmate::CIReport;
use Moose;

# ABSTRACT: summarize the artifacts of a CI run as a report for humans

use v5.36.0;
use utf8;

use JSON::XS ();
use Path::Tiny ();

=head1 OVERVIEW

A CIReport is built from a CI plan, the directory of artifacts retrieved from
the box by C<box ci-retrieve>, and the status the CI job itself decided on.  It
works out what happened to each test suite the plan called for, and renders
that as HTML and plain text, ready to be emailed.

The report's C<outcome> is one of:

=for :list
* success
Everything planned ran, and nothing failed.
* failure
Something went wrong in a way that means we can't say what passed or failed:
the box never produced artifacts, a step died, or a suite left no results.

=cut

has plan => (
  is       => 'ro',
  isa      => 'HashRef',
  required => 1,
);

has run_dir => (
  is       => 'ro',
  required => 1,
);

around BUILDARGS => sub ($orig, $class, @args) {
  my $arg = $class->$orig(@args);
  $arg->{run_dir} = Path::Tiny::path($arg->{run_dir}) if defined $arg->{run_dir};
  return $arg;
};

has status => (
  is       => 'ro',
  isa      => Moose::Util::TypeConstraints::enum([ qw( pass fail ) ]),
  required => 1,
);

# Information about the CI job, used to link back to it.  All optional.  Keys
# are job_url, pipeline_url, project_url, and ref.
has ci_info => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub {  {}  },
);

has produced_at => (
  is      => 'ro',
  default => sub { time },
);

has events => (
  is       => 'ro',
  lazy     => 1,
  init_arg => undef,
  builder  => '_build_events',
);

sub _build_events ($self) {
  my $file = $self->run_dir->child('events.json');
  return undef unless -e $file;

  return eval { JSON::XS->new->utf8->decode($file->slurp_raw) };
}

sub _plan_has_step ($self, $name) {
  return !! grep {; $_->[0] eq $name } $self->plan->{program}->@*;
}

sub _lines_of ($self, $filename) {
  my $file = $self->run_dir->child($filename);
  return undef unless -e $file;

  return [ grep {; length } map {; s/\s+\Z//r } $file->lines_utf8 ];
}

sub _last_event_for ($self, $slug) {
  my $events = $self->events;
  return undef unless $events;

  my ($event) = reverse grep {; $_->{slug} eq $slug } $events->{events}->@*;
  return $event;
}

my sub _event_failed ($event) {
  return $event && $event->{result}{status_code} != 0;
}

=method suites

This returns an arrayref of hashrefs, one per test suite the report knows
about.  Each has a C<name>, a C<state> (C<passed>, C<failed>, C<broken>, or
C<not-run>), and, depending on state, C<total>, C<unit> (what C<total>
counts), C<failures> (an arrayref of strings), and C<why> (an explanation of
why it's broken).  A broken suite has no C<why> when the whole run left no
results; that reason is given by C<trouble> instead.

=cut

has suites => (
  is       => 'ro',
  lazy     => 1,
  init_arg => undef,
  builder  => '_build_suites',
);

sub _build_suites ($self) {
  return [
    $self->_newt_suite,
    $self->_cassandane_suite,
  ];
}

sub _newt_suite ($self) {
  my %suite = (name => 'Fastmail', unit => 'test files');

  return { %suite, state => 'not-run' } unless $self->_plan_has_step('newt_full');

  return { %suite, state => 'broken' } if $self->_why_no_results;

  my $file_count = $self->events->{newt}{file_count};
  my $failures   = $self->_lines_of('newt_failures');

  unless (defined $file_count and $failures) {
    return {
      %suite,
      state => 'broken',
      why   => "The test run left no summary of its results.",
    };
  }

  $suite{total} = $file_count;

  return { %suite, state => 'failed', failures => $failures } if @$failures;

  if (_event_failed($self->_last_event_for('yath')) or ! $file_count) {
    return {
      %suite,
      state => 'broken',
      why   => "The test run failed, but no test files failed.",
    };
  }

  return { %suite, state => 'passed' };
}

sub _cassandane_suite ($self) {
  my %suite = (name => 'Cassandane', unit => 'tests');

  return { %suite, state => 'not-run' } unless $self->_plan_has_step('cassandane');

  return { %suite, state => 'broken' } if $self->_why_no_results;

  my $log = $self->_lines_of('cassandane.log');

  unless ($log && @$log) {
    return {
      %suite,
      state => 'broken',
      why   => "Cassandane left no log.",
    };
  }

  my $ok_count = grep {; /^\[\s*OK\s*\]/ } @$log;
  my $failures = $self->_lines_of('cass_failed') // [];

  $suite{total} = $ok_count + @$failures;

  return { %suite, state => 'failed', failures => $failures } if @$failures;

  if (_event_failed($self->_last_event_for('cassandane')) or ! $ok_count) {
    return {
      %suite,
      state => 'broken',
      why   => "The test run failed, but no tests failed.",
    };
  }

  return { %suite, state => 'passed' };
}

# If there's no artifact directory or no events file, we can't know anything
# about any suite, and we say so the same way for each.
sub _why_no_results ($self) {
  return "No artifacts were retrieved from the box." unless -d $self->run_dir;
  return "The box produced no events.json." unless $self->events;

  if (my $fatal = $self->events->{fatal_error}) {
    return "The run died during the $fatal->{step} step."
  }

  return;
}

=method failed_steps

This returns an arrayref of hashrefs describing commands that failed during
the run, other than the test suites themselves (which are described by
C<suites>).  Each has a C<slug> and a C<result>, which is a string
describing how it failed.

=cut

has failed_steps => (
  is       => 'ro',
  lazy     => 1,
  init_arg => undef,
  builder  => '_build_failed_steps',
);

sub _build_failed_steps ($self) {
  my $events = $self->events;
  return [] unless $events;

  my %is_suite = map {; $_ => 1 } qw( yath cassandane );

  my @failed;

  for my $event ($events->{events}->@*) {
    next if $is_suite{ $event->{slug} };
    next if ($event->{on_fail} // '') eq 'ignore';
    next unless _event_failed($event);

    my $result = $event->{result};
    push @failed, {
      slug   => $event->{slug},
      result => $result->{exitstatus}
              ? "exited $result->{exitstatus}"
              : "failed with status code $result->{status_code}",
    };
  }

  return \@failed;
}

has outcome => (
  is       => 'ro',
  lazy     => 1,
  init_arg => undef,
  builder  => '_build_outcome',
);

sub _build_outcome ($self) {
  my @states = map {; $_->{state} } $self->suites->@*;

  return 'trouble' if $self->trouble;
  return 'trouble' if grep {; $_ eq 'broken' } @states;
  return 'failure' if grep {; $_ eq 'failed' } @states;
  return 'failure' if $self->failed_steps->@*;

  return 'success';
}

=method trouble

This returns a list of strings describing problems with the run as a whole,
as opposed to with one suite, that kept the report from saying what happened.
If it's non-empty, the outcome is C<trouble>.

=cut

sub trouble ($self) {
  if (my $why = $self->_why_no_results) {
    my $fatal = $self->events && $self->events->{fatal_error};
    return ($why, ($fatal ? "Error from $fatal->{step}: $fatal->{error}" : ()));
  }

  my @trouble;

  # The CI job thinks it failed, but we found nothing wrong.  Take note!
  if ($self->status eq 'fail') {
    my $found_failure = $self->failed_steps->@*
                     || grep {; $_->{state} eq 'failed' || $_->{state} eq 'broken' } $self->suites->@*;

    push @trouble, "The CI job failed, but no failures were found in its results."
      unless $found_failure;
  }

  return @trouble;
}

my %SUBJECT = (
  success => "✅ CI Report: Success",
  failure => "❌ CI Report: Failure",
  trouble => "😱 CI Report: Something's wrong",
);

my %HEADLINE = (
  success => "Success!",
  failure => "Failure!",
  trouble => "Something's wrong!",
);

sub subject ($self, $tag = undef) {
  return join q{ }, $SUBJECT{ $self->outcome }, (defined $tag ? $tag : ());
}

sub _run_facts ($self) {
  my $events = $self->events // {};
  my $ci     = $self->ci_info;

  my $hm_head = $events->{hm_head};

  require DateTime;
  my $when = DateTime->from_epoch(
    epoch     => $self->produced_at,
    time_zone => 'America/New_York',
  )->format_cldr('cccc, MMM d, yyyy');

  return {
    box_version   => $events->{box_version}   // 'unknown',
    cyrus_version => $events->{cyrus_version} // 'unknown',
    hm_head       => defined $hm_head ? substr($hm_head, 0, 12) : 'unknown',
    hm_head_url   => ($hm_head && $ci->{project_url})
                   ? "$ci->{project_url}/-/commit/$hm_head"
                   : undef,
    artifacts_url => ($ci->{job_url} && -d $self->run_dir)
                   ? "$ci->{job_url}/artifacts/browse/" . $self->run_dir->basename . "/"
                   : undef,
    ref           => $ci->{ref},
    when          => $when,
  };
}

sub _suite_heading ($suite) {
  my $name = $suite->{name};

  return "⚠️ The $name test run couldn't be evaluated" if $suite->{state} eq 'broken';

  if ($suite->{state} eq 'failed') {
    my $n = $suite->{failures}->@*;
    return "❌ $n of $suite->{total} $name $suite->{unit} failed:";
  }

  return "✅ All $suite->{total} $name $suite->{unit} passed."
    if $suite->{state} eq 'passed';

  return "No $name tests were run.";
}

my sub _h ($str) {
  my %entity = ('&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;');
  return $str =~ s/([&<>"'])/$entity{$1}/gr;
}

=method text

This returns the report as plain text.

=cut

sub text ($self) {
  my $facts = $self->_run_facts;
  my $ci    = $self->ci_info;

  my $text = "Test Results\n============\n\n";

  $text .= "Results for box version $facts->{box_version}, "
        .  "hm commit $facts->{hm_head}"
        .  (defined $facts->{ref} ? " ($facts->{ref})" : "")
        .  ", using Cyrus $facts->{cyrus_version}, produced $facts->{when}.\n\n";

  $text .= "$HEADLINE{ $self->outcome }\n\n";

  if (my @trouble = $self->trouble) {
    $text .= "  * $_\n" for @trouble;
    $text .= "\n";
  }

  for my $suite ($self->suites->@*) {
    $text .= _suite_heading($suite) . "\n";
    $text .= "  $suite->{why}\n" if $suite->{why};
    $text .= "  - $_\n" for ($suite->{failures} // [])->@*;
    $text .= "\n";
  }

  if (my @failed = $self->failed_steps->@*) {
    $text .= "These steps failed:\n";
    $text .= "  - $_->{slug}: $_->{result}\n" for @failed;
    $text .= "\n";
  }

  $text .= "Job: $ci->{job_url}\n"              if $ci->{job_url};
  $text .= "Artifacts: $facts->{artifacts_url}\n" if $facts->{artifacts_url};
  $text .= "Pipeline: $ci->{pipeline_url}\n"    if $ci->{pipeline_url};

  return $text;
}

=method html

This returns the report as an HTML fragment.

=cut

sub html ($self) {
  my $facts = $self->_run_facts;
  my $ci    = $self->ci_info;

  my $commit = $facts->{hm_head_url}
             ? sprintf("<a href='%s'>%s</a>", _h($facts->{hm_head_url}), _h($facts->{hm_head}))
             : _h($facts->{hm_head});

  my $html = "<h1>Test Results</h1>\n\n";

  $html .= "<p>Results for box version " . _h($facts->{box_version})
        .  ", hm commit $commit"
        .  (defined $facts->{ref} ? " (" . _h($facts->{ref}) . ")" : "")
        .  ", using Cyrus " . _h($facts->{cyrus_version})
        .  ", produced " . _h($facts->{when}) . ".</p>\n\n";

  $html .= "<h2>$HEADLINE{ $self->outcome }</h2>\n\n";

  if (my @trouble = $self->trouble) {
    $html .= "<ul>\n";
    $html .= "<li>" . _h($_) . "</li>\n" for @trouble;
    $html .= "</ul>\n\n";
  }

  for my $suite ($self->suites->@*) {
    my $heading = _h(_suite_heading($suite));

    if ($suite->{state} eq 'not-run') {
      $html .= "<p><small>$heading</small></p>\n\n";
      next;
    }

    $html .= "<h3>$heading</h3>\n";
    $html .= "<p>" . _h($suite->{why}) . "</p>\n" if $suite->{why};

    if (my @failures = ($suite->{failures} // [])->@*) {
      $html .= "<ul>\n";
      $html .= "<li>" . _h($_) . "</li>\n" for @failures;
      $html .= "</ul>\n";
    }

    $html .= "\n";
  }

  if (my @failed = $self->failed_steps->@*) {
    $html .= "<h3>These steps failed:</h3>\n<ul>\n";
    $html .= "<li>" . _h("$_->{slug}: $_->{result}") . "</li>\n" for @failed;
    $html .= "</ul>\n\n";
  }

  if ($facts->{artifacts_url}) {
    $html .= sprintf "<p>See <a href='%s'>the CI job</a> for logs, and <a href='%s'>its artifacts</a> for everything the box produced.</p>\n\n",
      _h($ci->{job_url}), _h($facts->{artifacts_url});
  } elsif ($ci->{job_url}) {
    $html .= sprintf "<p>See <a href='%s'>the CI job</a> for logs.</p>\n\n",
      _h($ci->{job_url});
  }

  $html .= "<div style='padding-top: 1em'><center>&#x1F48C;</center></div>\n";

  return $html;
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
