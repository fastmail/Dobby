package Dobby::Boxmate::App::Command::cireport;
use Dobby::Boxmate::App -command;

# ABSTRACT: mail a report on a CI run's results

use v5.36.0;
use utf8;

sub command_names {
  return qw(ci-report cireport);
}

sub abstract { 'mail a report on a CI run' }

sub usage_desc {
  '%c ci-report %o [PLANFILE]',
}

sub opt_spec {
  return (
    [ 'status=s',  'what the CI job decided: pass or fail' ],
    [ 'target=s',  'where ci-retrieve put the artifacts', { default => "." } ],
    [],
    [ 'to=s',      'send only to this address, instead of the usual places' ],
    [ 'tag=s',     'add a tag to the mail subject' ],
    [ 'dry-run|n', 'print the report instead of sending it' ],
  );
}

my $FROM    = { name => 'Synergy', email => 'synergy@fastmailsystem.com' };
my $ARCHIVE = { name => 'Fastmail Test Results Archive', email => 'test-results@role.fastmailteam.com' };
my $FAILURE = { name => 'Fastmail Plumbers', email => 'plumbing@fastmail.topicbox.com' };

sub validate_args ($self, $opt, $args) {
  @$args <= 1 || $self->usage->die;

  ($opt->status // '') =~ /\A(?:pass|fail)\Z/
    || $self->usage->die({ pre_text => "--status must be pass or fail\n\n" });

  my $plan_file = $args->[0] // $self->app->_default_plan_filename;
  -r $plan_file || die "Can't read plan file $plan_file!\n";

  unless ($opt->dry_run or $ENV{CI_REPORT_JMAP_TOKEN}) {
    die "\$CI_REPORT_JMAP_TOKEN isn't set, so the report can't be sent\n";
  }
}

sub _ci_info ($self) {
  my %info = (
    job_url      => $ENV{CI_JOB_URL},
    pipeline_url => $ENV{CI_PIPELINE_URL},
    ref          => $ENV{CI_COMMIT_REF_NAME},
  );

  delete $info{$_} for grep {; ! defined $info{$_} } keys %info;

  return \%info;
}

sub execute ($self, $opt, $args) {
  require Dobby::Boxmate::CIReport;
  require Path::Tiny;

  my $plan_file = $args->[0] // $self->app->_default_plan_filename;
  my $plan = $self->app->_read_plan_file($plan_file);

  my $report = Dobby::Boxmate::CIReport->new({
    plan    => $plan,
    run_dir => Path::Tiny::path($opt->target)->child("run-$plan->{run_id}"),
    status  => $opt->status,
    ci_info => $self->_ci_info,
  });

  my @to = $opt->to ? ({ email => $opt->to }) : ($ARCHIVE);
  my @cc = ($opt->to || $report->outcome eq 'success') ? () : ($FAILURE);

  my $subject = $report->subject($opt->tag);

  if ($opt->dry_run) {
    say "To: " . join q{, }, map {; $_->{email} } @to;
    say "Cc: " . join q{, }, map {; $_->{email} } @cc if @cc;
    say "Subject: $subject";
    say "";
    print $report->text;
    say "";
    say "-" x 72;
    say "";
    print $report->html;
    return;
  }

  my $token = $ENV{CI_REPORT_JMAP_TOKEN};

  if ($token =~ m{^opcli:}) {
    require Password::OnePassword::OPCLI;
    $token = Password::OnePassword::OPCLI->new->get_field($token);
  }

  require Dobby::Boxmate::JMAPSender;
  require IO::Async::Loop;

  my $sender = Dobby::Boxmate::JMAPSender->new({
    loop  => $self->app->_loop,
    token => $token,
  });

  $sender->send_email({
    from    => $FROM,
    to      => \@to,
    cc      => \@cc,
    subject => $subject,
    text    => $report->text,
    html    => $report->html,
  })->get;

  say "Sent report: $subject";

  return;
}

1;
